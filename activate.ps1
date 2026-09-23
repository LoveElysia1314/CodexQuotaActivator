#requires -Version 5.1
<#
CodexQuotaActivator - scheduled activation worker

Design:
- Runs silently when launched through run-hidden.vbs.
- Uses .NET ProcessStartInfo directly; no nested PowerShell process.
- Captures stdout/stderr separately in UTF-8.
- Hard timeout: 60 seconds per attempt.
- Retries once after 15 seconds.
- Uses `codex exec --ephemeral`, so no Codex session is persisted.
#>

$ErrorActionPreference = "Stop"

$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $InstallRoot "logs"
$LogFile = Join-Path $LogDir "activator.log"
$ConfigFile = Join-Path $InstallRoot "config.json"

$MaxAttempts = 2
$AttemptTimeoutSeconds = 60
$RetryDelaySeconds = 15

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# Explicit UTF-8 for PowerShell 5.1/native-process interoperability.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    [Console]::InputEncoding = $Utf8NoBom
    [Console]::OutputEncoding = $Utf8NoBom
    $global:OutputEncoding = $Utf8NoBom
}
catch {}

function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )

    $line = "[{0}] [{1}] {2}" -f `
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"), `
        $Level.ToUpperInvariant(), `
        $Message

    if (-not (Test-Path -LiteralPath $LogFile)) {
        [System.IO.File]::WriteAllText(
            $LogFile,
            $line + [Environment]::NewLine,
            (New-Object System.Text.UTF8Encoding($true))
        )
    }
    else {
        [System.IO.File]::AppendAllText(
            $LogFile,
            $line + [Environment]::NewLine,
            (New-Object System.Text.UTF8Encoding($true))
        )
    }
}

function Get-CodexCommand {
    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $config = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($config.codex_path -and (Test-Path -LiteralPath $config.codex_path)) {
                return [string]$config.codex_path
            }
        }
        catch {
            Write-Log "WARN" "Unable to read config.json: $($_.Exception.Message)"
        }
    }

    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd) {
        return [string]$cmd.Source
    }

    return $null
}

function Quote-ProcessArgument {
    param([string]$Argument)

    # Windows command-line quoting compatible with CommandLineToArgvW conventions.
    if ($null -eq $Argument) {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')

    $backslashes = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq '\') {
            $backslashes++
            continue
        }

        if ($ch -eq '"') {
            [void]$sb.Append(('\' * ($backslashes * 2 + 1)))
            [void]$sb.Append('"')
            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            [void]$sb.Append(('\' * $backslashes))
            $backslashes = 0
        }

        [void]$sb.Append($ch)
    }

    if ($backslashes -gt 0) {
        [void]$sb.Append(('\' * ($backslashes * 2)))
    }

    [void]$sb.Append('"')
    return $sb.ToString()
}

function Get-ProcessLaunchInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodexPath,

        [Parameter(Mandatory = $true)]
        [string[]]$CodexArgs
    )

    $extension = [System.IO.Path]::GetExtension($CodexPath).ToLowerInvariant()

    if ($extension -eq ".cmd" -or $extension -eq ".bat") {
        $cmdExe = Join-Path $env:SystemRoot "System32\cmd.exe"

        $inner = @(
            Quote-ProcessArgument $CodexPath
        )

        foreach ($arg in $CodexArgs) {
            $inner += Quote-ProcessArgument $arg
        }

        return [pscustomobject]@{
            FileName = $cmdExe
            Arguments = "/d /s /c " + (Quote-ProcessArgument ($inner -join " "))
        }
    }

    if ($extension -eq ".ps1") {
        $powershellExe = Join-Path $PSHOME "powershell.exe"

        $parts = @(
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            (Quote-ProcessArgument $CodexPath)
        )

        foreach ($arg in $CodexArgs) {
            $parts += Quote-ProcessArgument $arg
        }

        return [pscustomobject]@{
            FileName = $powershellExe
            Arguments = ($parts -join " ")
        }
    }

    $args = @()
    foreach ($arg in $CodexArgs) {
        $args += Quote-ProcessArgument $arg
    }

    return [pscustomobject]@{
        FileName = $CodexPath
        Arguments = ($args -join " ")
    }
}

function Stop-ProcessTree {
    param([int]$ProcessId)

    try {
        $taskkill = Join-Path $env:SystemRoot "System32\taskkill.exe"
        if (Test-Path -LiteralPath $taskkill) {
            & $taskkill /PID $ProcessId /T /F *> $null
        }
        else {
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        try {
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        }
        catch {}
    }
}

function Invoke-CodexAttempt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodexPath,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [int]$TimeoutSeconds = 60
    )

    $codexArgs = @(
        "exec",
        "--ephemeral",
        "--skip-git-repo-check",
        "--color",
        "never",
        $Prompt
    )

    $launch = Get-ProcessLaunchInfo -CodexPath $CodexPath -CodexArgs $codexArgs

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $launch.FileName
    $psi.Arguments = $launch.Arguments
    $psi.WorkingDirectory = $InstallRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    # Available on supported .NET Framework builds used by current Windows PowerShell 5.1.
    try {
        $psi.StandardOutputEncoding = $Utf8NoBom
        $psi.StandardErrorEncoding = $Utf8NoBom
    }
    catch {}

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{
                Success = $false
                TimedOut = $false
                ExitCode = $null
                Stdout = ""
                Stderr = "Process.Start() returned false."
            }
        }

        # Begin asynchronous reads immediately to avoid stdout/stderr pipe deadlocks.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $finished = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $finished) {
            Stop-ProcessTree -ProcessId $process.Id

            try {
                $process.WaitForExit(5000) | Out-Null
            }
            catch {}

            $stdout = ""
            $stderr = ""

            try { $stdout = $stdoutTask.Result } catch {}
            try { $stderr = $stderrTask.Result } catch {}

            return [pscustomobject]@{
                Success = $false
                TimedOut = $true
                ExitCode = $null
                Stdout = $stdout
                Stderr = $stderr
            }
        }

        # Ensure async readers have drained.
        $process.WaitForExit()

        $stdout = ""
        $stderr = ""

        try { $stdout = $stdoutTask.Result } catch {}
        try { $stderr = $stderrTask.Result } catch {}

        return [pscustomobject]@{
            Success = ($process.ExitCode -eq 0)
            TimedOut = $false
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            TimedOut = $false
            ExitCode = $null
            Stdout = ""
            Stderr = $_.Exception.Message
        }
    }
    finally {
        try { $process.Dispose() } catch {}
    }
}

function Compress-LogText {
    param(
        [string]$Text,
        [int]$MaxLength = 1600
    )

    if (-not $Text) {
        return ""
    }

    $clean = ($Text -replace "[\r\n]+", " ").Trim()

    if ($clean.Length -gt $MaxLength) {
        return $clean.Substring($clean.Length - $MaxLength)
    }

    return $clean
}

try {
    Write-Log "INFO" "Scheduled activation started."

    $codexPath = Get-CodexCommand

    if (-not $codexPath) {
        Write-Log "ERROR" "Codex CLI was not found. This scheduled run was skipped. Re-run setup.ps1 after installing Codex CLI."
        exit 2
    }

    # The prompt is generated from UTF-8 Base64 to avoid PowerShell 5.1 source-file
    # encoding issues on systems where scripts are saved without a UTF-8 BOM.
    $templateBase64 = "VGhpcyBjb252ZXJzYXRpb24gaXMgb25seSBmb3IgdGVzdGluZyBDb2RleCBDTEkgbmV0d29yayBjb25uZWN0aXZpdHkgYW5kIHRoZSBzY2hlZHVsZWQgYWN0aXZhdGlvbiBzY3JpcHQgZXhlY3V0aW9uIHBhdGguCkN1cnJlbnQgdGltZToge1RJTUV9ClBsZWFzZSByZXBseSBvbmx5IHdpdGggIlJlY2VpdmVkLiI="
    $template = [System.Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($templateBase64)
    )

    $timestamp = [DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")
    $prompt = $template.Replace("{TIME}", $timestamp)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Log "INFO" "Starting Codex attempt $attempt/$MaxAttempts using an ephemeral session."

        $result = Invoke-CodexAttempt `
            -CodexPath $codexPath `
            -Prompt $prompt `
            -TimeoutSeconds $AttemptTimeoutSeconds

        $stdoutSummary = Compress-LogText $result.Stdout
        $stderrSummary = Compress-LogText $result.Stderr

        if ($stdoutSummary) {
            Write-Log "CODEX" "stdout: $stdoutSummary"
        }

        if ($stderrSummary) {
            Write-Log "CODEX" "stderr: $stderrSummary"
        }

        if ($result.Success) {
            Write-Log "INFO" "Activation request completed successfully on attempt $attempt."
            exit 0
        }

        if ($result.TimedOut) {
            Write-Log "WARN" "Attempt $attempt exceeded the ${AttemptTimeoutSeconds}s hard timeout."
        }
        else {
            Write-Log "WARN" "Attempt $attempt failed (exit=$($result.ExitCode))."
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Log "INFO" "Retrying in $RetryDelaySeconds seconds."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    Write-Log "ERROR" "All activation attempts failed. This run ended without further retries; the next scheduled run will try again."
    exit 1
}
catch {
    Write-Log "ERROR" "Unhandled error: $($_.Exception.Message)"
    exit 1
}
