#Requires -Version 5.1
<#
.SYNOPSIS
    Links this repo's canonical configs into the locations each tool reads.

.DESCRIPTION
    Idempotent and re-runnable. Backs up any existing real file/dir before
    replacing it with a symlink (as <name>.bak-<timestamp>).

    Prereq: Windows Developer Mode ON so symlinks don't need admin
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
    Write-Host "Can't create symlinks on this machine yet." -ForegroundColor Red
    Write-Host "Do ONE of these, then re-run install.ps1:" -ForegroundColor Yellow
    Write-Host "  1) Enable Developer Mode (one-time, no admin needed afterwards):" -ForegroundColor Yellow
    Write-Host "       Settings > Privacy & security > For developers > Developer Mode = On" -ForegroundColor Gray
    Write-Host "  2) Or run this script from an elevated 'Run as administrator' PowerShell." -ForegroundColor Yellow
    Write-Host ""
    return
}

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

# --- Link map ---------------------------------------------------------------
Write-Host "dotfiles: linking from $RepoRoot" -ForegroundColor Cyan

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
