# ==============================================================================
# ollama-top (otop) — Windows 1-Click Installer
# Run via: irm https://raw.githubusercontent.com/glueck-it/ollama-top/main/install.ps1 | iex
# ==============================================================================

$targetDir = "$env:LOCALAPPDATA\Programs\ollama-top"
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

$scriptUrl = "https://raw.githubusercontent.com/glueck-it/ollama-top/main/ollama-top.ps1"
$targetScript = "$targetDir\ollama-top.ps1"
$cmdWrapper = "$targetDir\otop.cmd"

Write-Host "Downloading ollama-top..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $scriptUrl -OutFile $targetScript -UseBasicParsing

# Create batch wrapper so 'otop' works from any shell
Set-Content -Path $cmdWrapper -Value @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$targetScript" %*
"@

# Add to User PATH if not present
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$targetDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$targetDir", "User")
    $env:Path = "$env:Path;$targetDir"
    Write-Host "Added $targetDir to User PATH." -ForegroundColor Green
}

Write-Host ""
Write-Host "ollama-top installed successfully!" -ForegroundColor Green
Write-Host "Type 'otop' in any terminal to start monitoring." -ForegroundColor Yellow
Write-Host "Author: Frank Glück (Glück IT) — https://dozent.net" -ForegroundColor Gray
