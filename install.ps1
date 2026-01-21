#!/bin/bash

set -euo pipefail

# Ralph Installation Script for Windows (PowerShell)
# Installs Ralph CLI for OpenCode on Windows

$RALPH_REPO = "https://github.com/anomalyco/opencode"
$RALPH_INSTALL_DIR = if ($env:RALPH_INSTALL_DIR) { $env:RALPH_INSTALL_DIR } else { "C:\Program Files\Ralph" }
$RALPH_CONFIG_DIR = if ($env:RALPH_CONFIG_DIR) { $env:RALPH_CONFIG_DIR } else { "$env:USERPROFILE\.ralph" }

Write-Host "🚀 Installing Ralph for OpenCode..." -ForegroundColor Green
Write-Host ""

# Check for jq (required dependency)
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Write-Host "📦 Installing jq dependency..." -ForegroundColor Yellow
    # Try to install via chocolatey or scoop
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install jq -y
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install jq
    } else {
        Write-Host "❌ Could not install jq automatically. Please install jq manually:" -ForegroundColor Red
        Write-Host "   Chocolatey: choco install jq"
        Write-Host "   Scoop: scoop install jq"
        Write-Host "   Download: https://stedolan.github.io/jq/download/"
        exit 1
    }
    Write-Host "✅ jq installed" -ForegroundColor Green
}

# Check for OpenCode
if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    Write-Host "📦 OpenCode not found. Installing..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://opencode.ai/install.ps1" -OutFile "install-opencode.ps1"
    .\install-opencode.ps1
    Remove-Item "install-opencode.ps1"
    Write-Host "✅ OpenCode installed" -ForegroundColor Green
} else {
    Write-Host "✅ OpenCode found: $(Get-Command opencode | Select-Object -ExpandProperty Source)" -ForegroundColor Green
}

# Create config directory
Write-Host "📁 Setting up Ralph configuration..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $RALPH_CONFIG_DIR | Out-Null
New-Item -ItemType Directory -Force -Path "$RALPH_CONFIG_DIR\logs" | Out-Null
New-Item -ItemType Directory -Force -Path "$RALPH_CONFIG_DIR\examples" | Out-Null

# Download Ralph script
$RALPH_SCRIPT = "$RALPH_INSTALL_DIR\ralph.ps1"
Write-Host "📥 Downloading Ralph script..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "$RALPH_REPO/raw/main/ralph.ps1" -OutFile $RALPH_SCRIPT

# Ensure installation directory exists
New-Item -ItemType Directory -Force -Path $RALPH_INSTALL_DIR | Out-Null

# Initialize Ralph state
Write-Host "🔧 Initializing Ralph state..." -ForegroundColor Yellow
@{
    status = "idle"
    iteration = 0
    prompt = ""
    start_time = $null
    last_activity = $null
    context = ""
} | ConvertTo-Json | Out-File -FilePath "$RALPH_CONFIG_DIR\state.json"

@{
    iterations = @()
    total_time = 0
    success = $false
} | ConvertTo-Json | Out-File -FilePath "$RALPH_CONFIG_DIR\history.json"

"# Ralph Progress Log" | Out-File -FilePath "$RALPH_CONFIG_DIR\progress.md"

Write-Host ""
Write-Host "✅ Ralph installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📖 Quick Start:" -ForegroundColor Yellow
Write-Host "   ralph --help                    # Show help"
Write-Host "   ralph `"<task>`"               # Start a Ralph loop"
Write-Host "   ralph --status                  # Check loop status"
Write-Host ""
Write-Host "📂 Configuration: $RALPH_CONFIG_DIR"
Write-Host "📂 Examples: $RALPH_CONFIG_DIR\examples"
Write-Host ""
Write-Host "⚡ Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Try a simple task:"
Write-Host '      ralph "Create a hello.txt file. Output <promise>COMPLETE</promise> when done."'
Write-Host ""
Write-Host "   2. Check progress:"
Write-Host "      ralph --status"
Write-Host ""
Write-Host "   3. For complex tasks, create a prompt file:"
Write-Host "      ralph --prompt-file C:\path\to\your-prompt.txt"
Write-Host ""
Write-Host "📚 Documentation: $RALPH_REPO/blob/main/README.md" -ForegroundColor Cyan