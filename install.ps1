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

# --- Developer Mode check ---------------------------------------------------
$reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$devMode = (Get-ItemProperty -Path $reg -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($devMode -ne 1) {
    Write-Warning "Developer Mode looks OFF. Symlink creation may need an elevated shell."
    Write-Warning "Enable: Settings > Privacy & security > For developers > Developer Mode."
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

# PowerShell 7 profile
New-RepoSymlink "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" `
                "$RepoRoot\shell\Microsoft.PowerShell_profile.ps1"

# Pi -- uncomment once its global config path is confirmed
# New-RepoSymlink "$HOME\.pi\AGENTS.md" "$RepoRoot\ai\AGENTS.md"

Write-Host "done." -ForegroundColor Cyan
