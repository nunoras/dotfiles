#Requires -Version 5.1
<#
.SYNOPSIS
    Links this repo's canonical configs into the locations each tool reads,
    and applies machine preferences (Terminal look, env vars).

.DESCRIPTION
    Idempotent and re-runnable. Backs up any existing real file/dir before
    replacing it with a symlink (as <name>.bak-<timestamp>).

    Machine preferences (Windows Terminal appearance, env vars) apply even
    when symlinks can't be created yet, so the look still lands.

    Prereq for symlinks: Windows Developer Mode ON so they don't need admin
    (Settings > Privacy & security > For developers > Developer Mode).
    If it's off, run this from an elevated PowerShell instead.

.PARAMETER WhatIfLinks
    Preview the links that would be created, without changing anything.
#>
[CmdletBinding()]
param(
    [switch]$WhatIfLinks
)

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

# --- Symlink helper ---------------------------------------------------------
function New-RepoSymlink {
    param(
        [Parameter(Mandatory)] [string]$LinkPath,    # where the tool looks
        [Parameter(Mandatory)] [string]$TargetPath   # the file/dir in this repo
    )

    if (-not (Test-Path $TargetPath)) {
        Write-Host "  skip   (no source) $TargetPath" -ForegroundColor DarkGray
        return
    }

    $parent = Split-Path $LinkPath -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue

    # Already the correct symlink?
    if ($existing -and $existing.LinkType -eq 'SymbolicLink') {
        $resolvedTarget = (Resolve-Path $TargetPath).Path
        $resolvedLink   = (Resolve-Path $existing.Target -ErrorAction SilentlyContinue).Path
        if ($resolvedLink -eq $resolvedTarget) {
            Write-Host "  ok     $LinkPath" -ForegroundColor DarkGreen
            return
        }
    }

    if ($WhatIfLinks) {
        Write-Host "  WOULD  $LinkPath -> $TargetPath" -ForegroundColor Yellow
        return
    }

    # Back up an existing real file/dir (or stale link)
    if ($existing) {
        $backup = "$LinkPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item -LiteralPath $LinkPath -Destination $backup -Force
        Write-Host "  backup $LinkPath -> $backup" -ForegroundColor Yellow
    }

    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
    Write-Host "  link   $LinkPath -> $TargetPath" -ForegroundColor Green
}

# --- Windows Terminal appearance --------------------------------------------
# Merge repo appearance into profiles.defaults WITHOUT touching the machine's
# own profile list (so per-machine profiles like conda/VS survive). We can't
# symlink settings.json because Windows Terminal rewrites it atomically.
function Set-TerminalAppearance {
    param([Parameter(Mandatory)] [string]$AppearanceFile)

    if (-not (Test-Path $AppearanceFile)) { return }

    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    $settingsPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $settingsPath) {
        Write-Host "  skip   (Windows Terminal not found)" -ForegroundColor DarkGray
        return
    }

    $appearance = Get-Content $AppearanceFile -Raw | ConvertFrom-Json
    $settings   = Get-Content $settingsPath  -Raw | ConvertFrom-Json

    if (-not $settings.profiles) {
        $settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    foreach ($prop in $appearance.PSObject.Properties) {
        $settings.profiles.defaults | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }

    if ($WhatIfLinks) {
        Write-Host "  WOULD  apply Windows Terminal appearance -> $settingsPath" -ForegroundColor Yellow
        return
    }

    $settings | ConvertTo-Json -Depth 32 | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Host "  apply  Windows Terminal appearance -> defaults" -ForegroundColor Green
}

# --- Machine preferences (always run; no symlink/admin needed) ---------------
Write-Host "dotfiles: applying machine preferences" -ForegroundColor Cyan

# Silence the "a new PowerShell release is available" banner on every launch.
# Must be a real env var (read at process start, before the profile applies).
if ([Environment]::GetEnvironmentVariable('POWERSHELL_UPDATECHECK','User') -ne 'Off') {
    [Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK','Off','User')
    Write-Host "  set    POWERSHELL_UPDATECHECK=Off (user env)" -ForegroundColor Green
}

# Windows Terminal look (scheme, opacity, font, padding, cursor)
Set-TerminalAppearance "$RepoRoot\terminal\appearance.json"

# --- Symlink capability check -----------------------------------------------
# Symlinks on Windows need EITHER Developer Mode ON or an elevated shell.
# Probe it directly so we fail with clear guidance instead of half-linking.
$probeSrc  = Join-Path $env:TEMP "dotfiles_probe_$PID.src"
$probeLink = Join-Path $env:TEMP "dotfiles_probe_$PID.lnk"
Set-Content -Path $probeSrc -Value '' -Force
Remove-Item $probeLink -Force -ErrorAction SilentlyContinue
$canSymlink = $false
try { New-Item -ItemType SymbolicLink -Path $probeLink -Target $probeSrc -ErrorAction Stop | Out-Null; $canSymlink = $true } catch {}
Remove-Item $probeLink, $probeSrc -Force -ErrorAction SilentlyContinue

if (-not $canSymlink) {
    Write-Host ""
    Write-Host "Machine preferences applied. Skipping symlinks - can't create them yet." -ForegroundColor Yellow
    Write-Host "Do ONE of these, then re-run install.ps1 to link configs:" -ForegroundColor Yellow
    Write-Host "  1) Enable Developer Mode (one-time, no admin needed afterwards):" -ForegroundColor Yellow
    Write-Host "       Settings > Privacy & security > For developers > Developer Mode = On" -ForegroundColor Gray
    Write-Host "  2) Or run this script from an elevated 'Run as administrator' PowerShell." -ForegroundColor Yellow
    Write-Host ""
    return
}

# --- Link map ---------------------------------------------------------------
Write-Host "dotfiles: linking configs from $RepoRoot" -ForegroundColor Cyan

# Claude Code -- point its CLAUDE.md at the canonical AGENTS.md
New-RepoSymlink "$HOME\.claude\CLAUDE.md"     "$RepoRoot\ai\AGENTS.md"
New-RepoSymlink "$HOME\.claude\skills"        "$RepoRoot\ai\skills"
New-RepoSymlink "$HOME\.claude\agents"        "$RepoRoot\ai\agents"
New-RepoSymlink "$HOME\.claude\settings.json" "$RepoRoot\claude\settings.json"

# Zed (Windows-native GUI app)
New-RepoSymlink "$env:APPDATA\Zed\settings.json" "$RepoRoot\zed\settings.json"
New-RepoSymlink "$env:APPDATA\Zed\keymap.json"   "$RepoRoot\zed\keymap.json"

# PowerShell 7 profile + bundled oh-my-posh theme (kept side by side so the
# profile finds the theme via $PSScriptRoot)
New-RepoSymlink "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" `
                "$RepoRoot\shell\Microsoft.PowerShell_profile.ps1"
New-RepoSymlink "$HOME\Documents\PowerShell\theme.omp.json" `
                "$RepoRoot\shell\theme.omp.json"

# Pi -- uncomment once its global config path is confirmed
# New-RepoSymlink "$HOME\.pi\AGENTS.md" "$RepoRoot\ai\AGENTS.md"

Write-Host "done." -ForegroundColor Cyan
