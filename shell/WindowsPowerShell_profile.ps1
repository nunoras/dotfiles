# Windows PowerShell 5.1 profile.
#
# Deliberately near-empty. The real shell setup lives in the pwsh 7 profile
# (Microsoft.PowerShell_profile.ps1) and is not loaded here, because 5.1 is not
# the shell this machine is set up around.
#
# This file exists for one reason: herdr spawns
# System32\WindowsPowerShell\v1.0\powershell.exe for its panes, which reads this
# profile and never the pwsh one. Without it, a new pane would just sit at a
# prompt instead of starting its agent.

# --- claude system-prompt append --------------------------------------------
# Wraps `claude` so every session gets ai/system-prompt-append.md. Shared with
# the other PowerShell profile for the same reason as the autostart below.
$__claudeWrapper = Join-Path $HOME '.claude\scripts\claude-wrapper.ps1'
if (Test-Path $__claudeWrapper) { . $__claudeWrapper }

# --- herdr pane autostart ---------------------------------------------------
# Starts claude in every herdr pane. Last on purpose: whatever the agent is,
# the shell you drop back into when it exits is already set up.
function lantern { herdr plugin action invoke aigora.lantern.open }

$__herdrAutostart = Join-Path $HOME '.claude\scripts\herdr-autostart.ps1'
if (Test-Path $__herdrAutostart) { . $__herdrAutostart }
