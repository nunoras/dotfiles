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

# Pause before closing when running in a standalone window (double-click / Run with PowerShell).
# WT_SESSION is set by Windows Terminal; its absence means this is a fresh throwaway window.
function Invoke-PauseIfStandalone {
    if (-not $env:WT_SESSION) {
        Write-Host "`nPress any key to close..." -NoNewline -ForegroundColor DarkGray
        try { [Console]::ReadKey($true) | Out-Null } catch {}
    }
}
trap { Write-Host "ERROR: $_" -ForegroundColor Red; Invoke-PauseIfStandalone; break }

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
    param(
        [Parameter(Mandatory)] [string]$AppearanceFile,
        [string]$SchemesFile,
        [string]$KeybindingsFile
    )

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

    # Merge custom color schemes by name (so non-built-in schemes travel along)
    if ($SchemesFile -and (Test-Path $SchemesFile)) {
        $ourSchemes = @(Get-Content $SchemesFile -Raw | ConvertFrom-Json)
        $merged = @($settings.schemes | Where-Object { $_ })
        foreach ($sc in $ourSchemes) {
            $merged = @($merged | Where-Object { $_.name -ne $sc.name })
            $merged += $sc
        }
        $settings | Add-Member -NotePropertyName schemes -NotePropertyValue $merged -Force
    }

    # Merge keybindings by their key chord (so custom binds travel along)
    if ($KeybindingsFile -and (Test-Path $KeybindingsFile)) {
        $ourBinds = @(Get-Content $KeybindingsFile -Raw | ConvertFrom-Json)
        $merged = @($settings.keybindings | Where-Object { $_ })
        foreach ($kb in $ourBinds) {
            $merged = @($merged | Where-Object { $_.keys -ne $kb.keys })
            $merged += $kb
        }
        $settings | Add-Member -NotePropertyName keybindings -NotePropertyValue $merged -Force
    }

    if ($WhatIfLinks) {
        Write-Host "  WOULD  apply Windows Terminal appearance + schemes -> $settingsPath" -ForegroundColor Yellow
        return
    }

    $settings | ConvertTo-Json -Depth 32 | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Host "  apply  Windows Terminal appearance + schemes -> defaults" -ForegroundColor Green
}

# --- Symlink capability -----------------------------------------------------
# Symlinks on Windows need EITHER Developer Mode ON or an elevated shell.
$DevModeKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$DevModeName = 'AllowDevelopmentWithoutDevLicense'

function Test-CanSymlink {
    $src  = Join-Path $env:TEMP "dotfiles_probe_$PID.src"
    $link = Join-Path $env:TEMP "dotfiles_probe_$PID.lnk"
    Set-Content -Path $src -Value '' -Force
    Remove-Item $link -Force -ErrorAction SilentlyContinue
    $ok = $false
    try { New-Item -ItemType SymbolicLink -Path $link -Target $src -ErrorAction Stop | Out-Null; $ok = $true } catch {}
    Remove-Item $link, $src -Force -ErrorAction SilentlyContinue
    return $ok
}

function Test-DeveloperMode {
    (Get-ItemProperty -Path $DevModeKey -Name $DevModeName -ErrorAction SilentlyContinue).$DevModeName -eq 1
}

# Turn Developer Mode on so symlinks never need admin again. Writing the HKLM
# flag itself needs admin, so when we're not elevated we self-elevate a single
# scoped command (one UAC prompt). Idempotent and best-effort: declining the
# prompt just leaves the caller on the manual-guidance fallback below.
function Enable-DeveloperMode {
    if (Test-DeveloperMode) {
        Write-Host "  ok     Developer Mode already on" -ForegroundColor DarkGreen
        return
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        New-Item -Path $DevModeKey -Force | Out-Null
        Set-ItemProperty -Path $DevModeKey -Name $DevModeName -Value 1 -Type DWord -Force
        Write-Host "  set    Developer Mode = On" -ForegroundColor Green
        return
    }

    Write-Host "  Developer Mode is off; requesting elevation to enable it (accept the UAC prompt)..." -ForegroundColor Yellow
    $elevatedCmd = "New-Item -Path '$DevModeKey' -Force | Out-Null; " +
                   "Set-ItemProperty -Path '$DevModeKey' -Name '$DevModeName' -Value 1 -Type DWord -Force"
    try {
        $psExe = (Get-Process -Id $PID).Path     # current powershell/pwsh host
        Start-Process -FilePath $psExe -Verb RunAs -Wait `
            -ArgumentList '-NoProfile','-Command',$elevatedCmd
    } catch {
        Write-Host "  skip   couldn't elevate ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}

# --- Machine preferences (always run; no symlink/admin needed) ---------------
Write-Host "dotfiles: applying machine preferences" -ForegroundColor Cyan

# Silence the "a new PowerShell release is available" banner on every launch.
# Must be a real env var (read at process start, before the profile applies).
if ([Environment]::GetEnvironmentVariable('POWERSHELL_UPDATECHECK','User') -ne 'Off') {
    [Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK','Off','User')
    Write-Host "  set    POWERSHELL_UPDATECHECK=Off (user env)" -ForegroundColor Green
}

# Enable Windows transparency effects, or terminal acrylic/opacity does nothing.
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if ((Get-ItemProperty -Path $personalize -Name EnableTransparency -ErrorAction SilentlyContinue).EnableTransparency -ne 1) {
    Set-ItemProperty -Path $personalize -Name EnableTransparency -Value 1
    Write-Host "  set    Windows transparency effects = On" -ForegroundColor Green
}

# Windows Terminal look (defaults) + custom schemes + opacity keybindings
Set-TerminalAppearance "$RepoRoot\terminal\appearance.json" `
                       "$RepoRoot\terminal\schemes.json" `
                       "$RepoRoot\terminal\keybindings.json"

# CaskaydiaCove Nerd Font (required by terminal/appearance.json)
$fontInstalled = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue).PSObject.Properties.Name +
                 (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue).PSObject.Properties.Name |
                 Where-Object { $_ -like '*CaskaydiaCove*' -or $_ -like '*Caskaydia Cove*' }
if ($fontInstalled) {
    Write-Host "  ok     CaskaydiaCove Nerd Font already installed" -ForegroundColor DarkGreen
} elseif (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    Write-Host "  install CaskaydiaCove Nerd Font via oh-my-posh..." -ForegroundColor Cyan
    oh-my-posh font install CascadiaCode
    Write-Host "  done   CaskaydiaCove Nerd Font" -ForegroundColor Green
} else {
    Write-Host "  skip   CaskaydiaCove Nerd Font (oh-my-posh not found; install manually from nerdfonts.com)" -ForegroundColor Yellow
}

# --- Ensure we can create symlinks (real runs only) -------------------------
# Probe directly; if we can't, try to enable Developer Mode (self-elevating once
# via UAC) and probe again, so a fresh machine links in a single pass instead of
# failing with manual guidance.
if (-not $WhatIfLinks) {
    Write-Host "dotfiles: checking symlink capability" -ForegroundColor Cyan
    if (-not (Test-CanSymlink)) { Enable-DeveloperMode }

    if (-not (Test-CanSymlink)) {
        Write-Host ""
        if (Test-DeveloperMode) {
            # Dev Mode is on now, but this shell started before it took effect;
            # a fresh process picks it up, so just re-run -- no manual toggle.
            Write-Host "Developer Mode is on now, but this shell started before that took effect." -ForegroundColor Yellow
            Write-Host "Open a new PowerShell and re-run install.ps1 to link configs." -ForegroundColor Yellow
        } else {
            Write-Host "Machine preferences applied. Skipping symlinks - can't create them yet." -ForegroundColor Yellow
            Write-Host "Do ONE of these, then re-run install.ps1 to link configs:" -ForegroundColor Yellow
            Write-Host "  1) Enable Developer Mode (one-time, no admin needed afterwards):" -ForegroundColor Yellow
            Write-Host "       Settings > Privacy & security > For developers > Developer Mode = On" -ForegroundColor Gray
            Write-Host "  2) Or run this script from an elevated 'Run as administrator' PowerShell." -ForegroundColor Yellow
        }
        Write-Host ""
        Invoke-PauseIfStandalone
        return
    }
}

# --- Link map ---------------------------------------------------------------
Write-Host "dotfiles: linking configs from $RepoRoot" -ForegroundColor Cyan

# Claude Code -- point its CLAUDE.md at the canonical AGENTS.md
New-RepoSymlink "$HOME\.claude\CLAUDE.md"     "$RepoRoot\ai\AGENTS.md"

# Appended to every Claude Code session's system prompt by the `claude` shim
# in shell/*_profile.ps1 -- Claude Code has no settings key for this, only a flag.
New-RepoSymlink "$HOME\.claude\system-prompt-append.md" "$RepoRoot\ai\system-prompt-append.md"
New-RepoSymlink "$HOME\.claude\skills"        "$RepoRoot\ai\skills"
New-RepoSymlink "$HOME\.claude\agents"        "$RepoRoot\ai\agents"
New-RepoSymlink "$HOME\.claude\scripts"       "$RepoRoot\ai\scripts"

# Model roster for pane orchestration -- read by the dispatch scripts and the
# to-tickets skill. A well-known path so non-PowerShell consumers find it too.
New-RepoSymlink "$HOME\.claude\roster.json"   "$RepoRoot\ai\roster.json"
New-RepoSymlink "$HOME\.pi\agent\roster.json" "$RepoRoot\ai\roster.json"
New-RepoSymlink "$HOME\.claude\settings.json" "$RepoRoot\claude\settings.json"

# Claude Code status line (settings.json points at this path)
New-RepoSymlink "$HOME\.claude\statusline-rich.ps1" "$RepoRoot\claude\statusline-rich.ps1"

# Claude Code hooks -- linked file by file, so hooks that other tools drop into
# ~/.claude/hooks (plugin self-healers, etc.) are left alone.
New-RepoSymlink "$HOME\.claude\hooks\unslop-always.ps1"     "$RepoRoot\claude\hooks\unslop-always.ps1"

# Zed (Windows-native GUI app)
New-RepoSymlink "$env:APPDATA\Zed\settings.json" "$RepoRoot\zed\settings.json"
New-RepoSymlink "$env:APPDATA\Zed\keymap.json"   "$RepoRoot\zed\keymap.json"

# PowerShell 7 profile + bundled oh-my-posh theme (kept side by side so the
# profile finds the theme via $PSScriptRoot)
New-RepoSymlink "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" `
                "$RepoRoot\shell\Microsoft.PowerShell_profile.ps1"
New-RepoSymlink "$HOME\Documents\PowerShell\theme.omp.json" `
                "$RepoRoot\shell\theme.omp.json"

# Pi -- settings, extensions, and skills are canonical in this repo.
# AGENTS.md is shared with Claude (same canonical file).
New-RepoSymlink "$HOME\.pi\agent\AGENTS.md"    "$RepoRoot\ai\AGENTS.md"
New-RepoSymlink "$HOME\.pi\agent\settings.json" "$RepoRoot\pi\settings.json"
New-RepoSymlink "$HOME\.pi\agent\extensions"    "$RepoRoot\pi\extensions"
New-RepoSymlink "$HOME\.pi\agent\skills"        "$RepoRoot\pi\skills"

Write-Host "done." -ForegroundColor Cyan
Invoke-PauseIfStandalone
