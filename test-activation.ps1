#requires -Version 5.1
# One-shot manual check. This sends one real Codex request and does not retry.
$ErrorActionPreference = "Stop"

$configFile = Join-Path $PSScriptRoot "config.json"
$codexPath = $null

if (Test-Path -LiteralPath $configFile) {
    $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.codex_path -and (Test-Path -LiteralPath $config.codex_path)) {
        $codexPath = [string]$config.codex_path
    }
}

if (-not $codexPath) {
    $command = Get-Command codex -ErrorAction SilentlyContinue
    if ($command) {
        $codexPath = [string]$command.Source
    }
}

if (-not $codexPath) {
    throw "Codex CLI was not found. Install it or run setup.ps1 first."
}

Push-Location -LiteralPath $PSScriptRoot
try {
    & $codexPath exec `
        --ephemeral `
        --skip-git-repo-check `
        --model gpt-6-luna `
        --config model_reasoning_effort=low `
        --color never `
        "Ping. Reply PONG."

    $exitCode = $LASTEXITCODE
    Write-Host "Codex exit code: $exitCode"
    exit $exitCode
}
finally {
    Pop-Location
}
