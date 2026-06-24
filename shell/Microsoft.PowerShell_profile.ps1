# PowerShell 7 profile — synced via dotfiles.
# Recreates the WSL + oh-my-zsh experience natively on Windows.
# Every block is guarded, so it won't error if a tool isn't installed yet.

# Oh My Posh — prompt theme engine (the oh-my-zsh / Powerlevel10k analog)
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression
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
    if ($psrl.Version -ge [version]'2.2.0') {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView
    } elseif ($psrl.Version -ge [version]'2.1.0') {
        Set-PSReadLineOption -PredictionSource History
    }
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# PSFzf — fuzzy history (Ctrl+r) and file picker (Ctrl+t)
if (Get-Module -ListAvailable -Name PSFzf) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# Terminal-Icons — file-type glyphs in `ls` output
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# --- aliases & functions ----------------------------------------------------
# Set-Alias ll Get-ChildItem
# Set-Alias g  git
