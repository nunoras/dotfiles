#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the apps and tools the dotfiles configure, then links the configs.
    Fresh machine = git clone -> bootstrap.ps1.

.DESCRIPTION
    Idempotent: winget / Install-Module skip what's already installed.
    Tolerant: a failure on one item is reported; the rest continue.
    Runs fine from stock Windows PowerShell 5.1.

.PARAMETER SkipInstall
    Install software only; don't run install.ps1 (config linking) at the end.
#>
[CmdletBinding()]
param([switch]$SkipInstall)

$ErrorActionPreference = 'Continue'
$RepoRoot = $PSScriptRoot

# --- winget present? --------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "winget not found. Install 'App Installer' from the Microsoft Store, then re-run." -ForegroundColor Red
    return
}

# --- Apps via winget --------------------------------------------------------
Write-Host "bootstrap: installing apps via winget" -ForegroundColor Cyan
$packages = @(
    'Microsoft.PowerShell',        # pwsh 7 - the target shell
    'Microsoft.WindowsTerminal',   # terminal host
    'JanDeDobbeleer.OhMyPosh',     # prompt engine
    'ajeetdsouza.zoxide',          # smart cd (z)
    'junegunn.fzf',                # fuzzy finder
    'Git.Git',                     # git
    'GitHub.cli',                  # gh (repo + collector workflow)
    'ZedIndustries.Zed'            # editor
)
foreach ($id in $packages) {
    Write-Host "  -> $id" -ForegroundColor Gray
    winget install --id $id -e --source winget --accept-source-agreements --accept-package-agreements --silent | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "     installed" -ForegroundColor Green }
    else { Write-Host "     already present or skipped (winget code $LASTEXITCODE)" -ForegroundColor DarkGray }
}

# Refresh PATH so freshly-installed exes (oh-my-posh, git, ...) are callable now
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

# --- PowerShell modules -----------------------------------------------------
Write-Host "bootstrap: installing PowerShell modules" -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($m in 'PSFzf','Terminal-Icons') {
    if (Get-Module -ListAvailable -Name $m) { Write-Host "  ok    $m" -ForegroundColor DarkGreen; continue }
    try {
        Install-Module $m -Scope CurrentUser -Force -AcceptLicense -ErrorAction Stop
        Write-Host "  add   $m" -ForegroundColor Green
    } catch { Write-Host "  fail  $m - $($_.Exception.Message)" -ForegroundColor Yellow }
}

# --- Nerd Font (CaskaydiaCove) ----------------------------------------------
# The profile + terminal expect "CaskaydiaCove Nerd Font" (oh-my-posh glyphs).
Write-Host "bootstrap: installing CaskaydiaCove Nerd Font" -ForegroundColor Cyan
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh font install CascadiaCode 2>$null
    Write-Host "  font  CascadiaCode (CaskaydiaCove) requested" -ForegroundColor Green
} else {
    Write-Host "  skip  oh-my-posh not on PATH yet; in a new shell run: oh-my-posh font install CascadiaCode" -ForegroundColor Yellow
}

# --- AI CLIs (optional; install methods vary, so left manual) ----------------
# Claude Code (via npm) -- needs Node.js:
#   winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
#   npm install -g @anthropic-ai/claude-code
# Pi -- add its install command here once confirmed.

# --- Link configs + apply look ----------------------------------------------
if (-not $SkipInstall) {
    Write-Host "`nbootstrap: running install.ps1" -ForegroundColor Cyan
    & "$RepoRoot\install.ps1"
}

Write-Host "`nbootstrap done." -ForegroundColor Cyan
Write-Host "Open a NEW Windows Terminal (pwsh) tab to load the profile, prompt, and theme." -ForegroundColor Cyan
