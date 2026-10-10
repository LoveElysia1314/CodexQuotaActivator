#requires -Version 5.1
<#
CodexQuotaActivator setup
Single merged entry for both install and uninstall.

The scheduled task runs the scripts from this folder. Keep the folder at the
same path after running install.cmd.

Run directly to get an interactive menu:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File setup.ps1

Or pass -Mode to run a specific action non-interactively:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Mode Install
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Mode Uninstall

install.cmd / uninstall.cmd are thin wrappers that call this script with the matching -Mode.
#>
param(
    [ValidateSet("Install", "Uninstall")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$TaskName = "Codex Quota Activator"

# Runtime files are generated in the project folder.
$Script:AppRoot = $PSScriptRoot

function Pause-IfInteractive {
    if ($Host.Name -notmatch "ServerRemoteHost") {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
function Find-Codex {
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd) {
        return [string]$cmd.Source
    }

    # If npm is present but its shim is not yet visible through command discovery,
    # try the global npm prefix as a fallback.
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) {
        $npm = Get-Command npm -ErrorAction SilentlyContinue
    }

    if ($npm) {
        try {
            $prefix = (& $npm.Source prefix -g 2>$null | Select-Object -First 1).Trim()
            if ($prefix) {
                foreach ($candidate in @(
                    (Join-Path $prefix "codex.cmd"),
                    (Join-Path $prefix "codex.ps1"),
                    (Join-Path $prefix "codex.exe")
                )) {
                    if (Test-Path -LiteralPath $candidate) {
                        return $candidate
                    }
                }
            }
        }
        catch {}
    }

    return $null
}

function Show-CodexInstallHelp {
    Write-Host ""
    Write-Host "Codex CLI was not found." -ForegroundColor Yellow
    Write-Host "Possible causes:"
    Write-Host "  - Codex CLI has not been installed."
    Write-Host "  - npm's global binary directory is not in PATH."
    Write-Host "  - Codex was installed in another Windows user profile."
    Write-Host ""
    Write-Host "Quick install:"
    Write-Host "  npm install -g @openai/codex@latest" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "If Node.js/npm is missing, install Node.js LTS first:"
    Write-Host "  winget install OpenJS.NodeJS.LTS" -ForegroundColor Cyan
    Write-Host "  npm install -g @openai/codex@latest" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "After installation, run 'codex' once and complete ChatGPT sign-in if needed."
}

function Try-InteractiveCodexInstall {
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) {
        $npm = Get-Command npm -ErrorAction SilentlyContinue
    }

    if (-not $npm) {
        return $false
    }

    Write-Host ""
    $answer = Read-Host "npm is available. Install/update Codex CLI now? [Y/N]"
    if ($answer -notmatch "^(?i:y|yes)$") {
        return $false
    }

    Write-Host "Installing @openai/codex@latest..."
    & $npm.Source install -g @openai/codex@latest

    if ($LASTEXITCODE -ne 0) {
        Write-Host "npm installation failed with exit code $LASTEXITCODE." -ForegroundColor Red
        return $false
    }

    return $true
}

function Test-EphemeralSupport {
    param([string]$CodexPath)

    try {
        $help = (& $CodexPath exec --help 2>&1 | Out-String)
        return ($help -match "(?m)--ephemeral\b")
    }
    catch {
        return $false
    }
}

function Install-CodexActivator {
    $SourceRoot = $PSScriptRoot
    $ActivationSource = Join-Path $SourceRoot "activate.ps1"
    $LauncherTarget = Join-Path $SourceRoot "run-hidden.vbs"
    $ConfigTarget = Join-Path $SourceRoot "config.json"
    $LogTarget = Join-Path $SourceRoot "logs"

    Write-Host "Codex Quota Activator installer"
    Write-Host "-------------------------------------------------"
    Write-Host "App folder (kept as-is): $SourceRoot"

    # The worker needs a writable folder for config.json and logs.
    try {
        New-Item -ItemType Directory -Path $LogTarget -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host ""
        Write-Host "Cannot write to the app folder ($SourceRoot)." -ForegroundColor Red
        Write-Host "Move this folder to a writable location (e.g. under your user profile) and run install.cmd again."
        Pause-IfInteractive
        exit 4
    }

    if (-not (Test-Path -LiteralPath $ActivationSource)) {
        throw "activate.ps1 is missing from the installer directory."
    }

    $codexPath = Find-Codex

    if (-not $codexPath) {
        Show-CodexInstallHelp
        [void](Try-InteractiveCodexInstall)
        $codexPath = Find-Codex
    }

    if (-not $codexPath) {
        Write-Host ""
        Write-Host "Installation stopped: Codex CLI is required before the scheduled task can be registered." -ForegroundColor Red
        Pause-IfInteractive
        exit 2
    }

    Write-Host ""
    Write-Host "Found Codex CLI:"
    Write-Host "  $codexPath" -ForegroundColor Green

    try {
        $version = (& $codexPath --version 2>&1 | Select-Object -First 1)
        if ($version) {
            Write-Host "  $version"
        }
    }
    catch {}

    if (-not (Test-EphemeralSupport -CodexPath $codexPath)) {
        Write-Host ""
        Write-Host "This Codex CLI does not expose 'codex exec --ephemeral'." -ForegroundColor Red
        Write-Host "Update it first:"
        Write-Host "  npm install -g @openai/codex@latest" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "No scheduled task was registered."
        Pause-IfInteractive
        exit 3
    }

    @{
        codex_path = $codexPath
        installed_at = [DateTimeOffset]::Now.ToString("o")
        schedule = "Daily at 05:30, 10:35, 15:40, and 20:45 local time"
    } | ConvertTo-Json | Set-Content -LiteralPath $ConfigTarget -Encoding UTF8

    # WScript launches PowerShell with window style 0, so scheduled runs are fully hidden.
    $escapedActivation = $ActivationSource.Replace('"', '""')
    $vbs = @"
Option Explicit
Dim shell, cmd
Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$escapedActivation"""
shell.Run cmd, 0, True
"@
    Set-Content -LiteralPath $LauncherTarget -Value $vbs -Encoding Unicode

    $wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
    $taskCommand = "`"$wscript`" //B //NoLogo `"$LauncherTarget`""
    Write-Host ""
    Write-Host "Registering one scheduled task with four daily triggers:"
    Write-Host "  05:30 / 10:35 / 15:40 / 20:45 (local time)"
    Write-Host "  Runs hidden via wscript.exe -> PowerShell -WindowStyle Hidden"
    Write-Host "  Script location: $LauncherTarget"

    # A single schtasks /Create command cannot add multiple unrelated daily
    # triggers, so register the task from XML instead.
    $taskXmlPath = Join-Path $env:TEMP ("CodexQuotaActivator-{0}.xml" -f [Guid]::NewGuid())
    $today = (Get-Date).Date.ToString("yyyy-MM-dd")
    $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $escapedCommand = [System.Security.SecurityElement]::Escape($wscript)
    $escapedLauncher = [System.Security.SecurityElement]::Escape($LauncherTarget)
    $triggers = @("05:30:00", "10:35:00", "15:40:00", "20:45:00") | ForEach-Object {
        @"
    <CalendarTrigger>
      <StartBoundary>${today}T$_</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
"@
    }
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Runs Codex Quota Activator at four daily local times.</Description>
  </RegistrationInfo>
  <Triggers>
$($triggers -join "`r`n")
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$userSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <AllowHardTerminate>true</AllowHardTerminate>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Hidden>false</Hidden>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$escapedCommand</Command>
      <Arguments>//B //NoLogo $escapedLauncher</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    try {
        [System.IO.File]::WriteAllText(
            $taskXmlPath,
            $taskXml,
            (New-Object System.Text.UnicodeEncoding($false, $true))
        )
        & schtasks.exe /Create /TN $TaskName /XML $taskXmlPath /F | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks.exe failed to register the scheduled task (exit code $LASTEXITCODE)."
        }
    }
    finally {
        Remove-Item -LiteralPath $taskXmlPath -Force -ErrorAction SilentlyContinue
    }

    & schtasks.exe /Query /TN $TaskName *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Scheduled task registration could not be verified."
    }

    Write-Host ""
    Write-Host "Installation completed." -ForegroundColor Green
    Write-Host "App folder:"
    Write-Host "  $SourceRoot"
    Write-Host "Log file:"
    Write-Host "  $(Join-Path $SourceRoot 'logs\activator.log')"
    Write-Host ""
    Write-Host "Keep this folder at the same path while the task is installed."
    Write-Host "Requests use 'codex exec --ephemeral' and do not persist CLI session rollout files."
    Write-Host "The task uses the machine's existing network configuration."
    Write-Host "Each attempt has a 60-second timeout; failures are retried once. Scheduled runs have no visible console window."

    Pause-IfInteractive
    exit 0
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
function Uninstall-CodexActivator {
    $ErrorActionPreference = "SilentlyContinue"

    $SourceRoot = $PSScriptRoot

    Write-Host "Codex Quota Activator uninstaller"
    Write-Host "-----------------------------------------------------"

    # 1) Remove the scheduled task only. This never touches the app folder.
    & schtasks.exe /Delete /TN $TaskName /F *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Scheduled task removed." -ForegroundColor Green
    }
    else {
        Write-Host "Scheduled task was not present, or could not be removed." -ForegroundColor Yellow
    }

    # 2) Remove runtime artifacts generated by install/run in this folder:
    #    logs/, config.json, run-hidden.vbs. Keep activate.ps1 & setup.ps1 so the
    #    project scripts remain available for later use.
    $generated = @(
        (Join-Path $SourceRoot "logs"),
        (Join-Path $SourceRoot "config.json"),
        (Join-Path $SourceRoot "run-hidden.vbs")
    )

    foreach ($path in $generated) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 3) Remove the folder only if no project files remain.
    $stillThere = @("activate.ps1", "setup.ps1", "install.cmd", "uninstall.cmd", "README.md") |
        Where-Object { Test-Path -LiteralPath (Join-Path $SourceRoot $_) }

    Write-Host ""
    if ($stillThere) {
        Write-Host "Project files remain in: $SourceRoot" -ForegroundColor Yellow
    }
    else {
        Write-Host "App folder is no longer needed; removing it: $SourceRoot" -ForegroundColor Green
        Remove-Item -LiteralPath $SourceRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "Uninstallation completed."
    Pause-IfInteractive
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
while ([string]::IsNullOrEmpty($Mode)) {
    Write-Host ""
    Write-Host "Codex Quota Activator - setup"
    Write-Host "--------------------------------"
    Write-Host "  1) Install  (detect Codex CLI and register the scheduled task)"
    Write-Host "  2) Uninstall  (remove the scheduled task and installed files)"
    Write-Host "  0) Exit"
    $choice = Read-Host "Select [0/1/2]"
    switch ($choice) {
        { $_ -in '1', 'I', 'i' } { $Mode = "Install" }
        { $_ -in '2', 'U', 'u' } { $Mode = "Uninstall" }
        { $_ -in '0', 'Q', 'q', '' } { exit 0 }
        default { Write-Host "Unrecognized option: $_" }
    }
}

if ($Mode -eq "Uninstall") {
    Uninstall-CodexActivator
}
else {
    try {
        Install-CodexActivator
    }
    catch {
        Write-Host ""
        Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "No further task registration will be attempted."
        Pause-IfInteractive
        exit 1
    }
}
