# PowerShell 7 profile — synced via dotfiles.
# Recreates the WSL + oh-my-zsh experience natively on Windows.
# Every block is guarded, so it won't error if a tool isn't installed yet.

# Oh My Posh — prompt theme engine (the oh-my-zsh / Powerlevel10k analog).
# Theme is bundled next to this profile so it travels with the repo (no
# dependency on oh-my-posh's themes folder existing on a given machine).
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $theme = Join-Path $PSScriptRoot 'theme.omp.json'
    if (Test-Path $theme) {
        oh-my-posh init pwsh --config $theme | Invoke-Expression
    } else {
        oh-my-posh init pwsh | Invoke-Expression
    }
}

# zoxide — smart directory jumping (the `z` / autojump analog). Use `z <dir>`.
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# PSReadLine — inline grey-text predictions (zsh-autosuggestions analog).
# Predictions need PSReadLine 2.1+ (ships with PowerShell 7); guard so this
# profile also loads cleanly under old Windows PowerShell 5.1 / PSReadLine 2.0.
$psrl = Get-Module -ListAvailable -Name PSReadLine | Sort-Object Version -Descending | Select-Object -First 1
if ($psrl) {
    Import-Module PSReadLine
    # try/catch: predictions need an interactive VT console; ignore when the
    # profile is loaded with redirected output (scripts, CI, capture).
    try {
        if ($psrl.Version -ge [version]'2.2.0') {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView
        } elseif ($psrl.Version -ge [version]'2.1.0') {
            Set-PSReadLineOption -PredictionSource History
        }
    } catch {}
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# PSFzf — fuzzy history (Ctrl+r) and file picker (Ctrl+t).
# Needs the fzf binary on PATH, so only load when both are present.
if ((Get-Module -ListAvailable -Name PSFzf) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# Terminal-Icons — file-type glyphs in `ls` output
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# --- claude system-prompt append --------------------------------------------
# Wraps `claude` so every session gets ai/system-prompt-append.md.
# Not $PSScriptRoot: this profile is a symlink, so that resolves to the link's
# directory rather than the dotfiles repo.
$__claudeWrapper = Join-Path $HOME '.claude\scripts\claude-wrapper.ps1'
if (Test-Path $__claudeWrapper) { . $__claudeWrapper }

# --- aliases & functions ----------------------------------------------------
# Set-Alias ll Get-ChildItem
# Set-Alias g  git

