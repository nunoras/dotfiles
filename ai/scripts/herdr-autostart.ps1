# Start an agent in a herdr pane shell.
#
# Two ways in:
#   - default: every interactive herdr pane starts pi (Nuno's call, 2026-08-25;
#     it was claude before that)
#   - explicit: the pane was opened with M2_AUTOSTART=<agent>, which wins over
#     the default (herdr-build.ps1 uses this for glm)
#
# Dot-sourced from both PowerShell profiles, because herdr spawns Windows
# PowerShell 5.1 (System32\WindowsPowerShell\v1.0\powershell.exe) rather than
# pwsh 7, and those two read different profile paths. Dot-source it LAST, so
# the shell you land in when the agent exits is fully configured.
#
# Why the pane's own shell starts the agent instead of herdr: `herdr agent
# start --kind claude` shells out to `Start-Process -FilePath claude`, which on
# a Windows npm install resolves to the extensionless `claude` (a /bin/sh
# script) instead of claude.cmd and fails with "%1 is not a valid Win32
# application". Letting the shell do it sidesteps that, and herdr's detection
# picks the agent up normally once it is running.
#
# Three guards, all of which must hold:
#   HERDR_PANE_ID  - this is a herdr pane, not some other console
#   -NoExit        - herdr launches its pane shells with it and scripted
#                    invocations do not, so it is the interactivity test
#   no CLAUDECODE  - this shell was not spawned by a running Claude Code
#                    session to run a tool call, which would recurse
#
# Escape hatches:
#   $env:M2_NO_AUTOSTART = 1   -> that pane opens at a plain prompt
#   $env:M2_AUTOSTART = 'claude' -> that pane starts Claude Code instead of pi
#   exit the agent             -> you land in this shell, nothing relaunches
#
# Pane-orchestration extras (set by dispatch.ps1 for the pi harness):
#   $env:M2_PROVIDER = 'zai'          -> pi launches with --provider zai
#   $env:M2_MODEL    = 'glm-5.3'      -> pi launches with --model glm-5.3
#   $env:M2_AUTOSTART_AGENT = 'builder' -> ~/.claude/agents/builder.md is
#                                       appended to the system prompt
#   $env:M2_READONLY = '1'            -> pi launches with write/edit/bash/
#                                       powershell excluded (reviewer panes)
# Provider+model must be passed as separate flags: `pi --model zai/glm-5.3`
# matches no id and silently falls back to the default Anthropic model.
#
# Keep this file PowerShell 5.1 compatible. No ??, no ?., no ternary.

$__herdrPaneShell = $false
if ($env:HERDR_PANE_ID -and (-not $env:CLAUDECODE)) {
    # -noe* matches -NoExit and its abbreviations and nothing else powershell
    # accepts: -nop is NoProfile, -nol NoLogo, -non NonInteractive.
    foreach ($__a in [Environment]::GetCommandLineArgs()) {
        if ($__a -like '-noe*') { $__herdrPaneShell = $true }
    }
}

if ($__herdrPaneShell -and (-not $env:M2_NO_AUTOSTART)) {
    $__autostart = $env:M2_AUTOSTART
    if (-not $__autostart) { $__autostart = 'pi' }

    # Cleared before launching so a nested shell cannot relaunch forever.
    Remove-Item Env:\M2_AUTOSTART -ErrorAction SilentlyContinue

    switch ($__autostart) {
        'pi' {
            # Prefer pi.cmd/pi.exe over the extensionless /bin/sh shim npm also
            # drops on PATH, same problem claude-wrapper.ps1 works around.
            $__pi = $null
            $__piCandidates = @(Get-Command 'pi' -CommandType Application -All -ErrorAction SilentlyContinue)
            foreach ($__c in $__piCandidates) {
                if ($__c.Source -like '*.cmd' -or $__c.Source -like '*.exe') { $__pi = $__c.Source; break }
            }
            if ((-not $__pi) -and $__piCandidates.Count -gt 0) { $__pi = $__piCandidates[0].Source }

            # Optional provider+model+agent, set by dispatch.ps1. Read and clear
            # so a nested shell cannot inherit them.
            $__provider = $env:M2_PROVIDER
            $__model    = $env:M2_MODEL
            $__agent    = $env:M2_AUTOSTART_AGENT
            $__readonly = $env:M2_READONLY
            Remove-Item Env:\M2_PROVIDER, Env:\M2_MODEL, Env:\M2_AUTOSTART_AGENT, Env:\M2_READONLY -ErrorAction SilentlyContinue

            # -a trusts the cwd's .pi files without asking. Combined with
            # defaultProjectTrust=always in settings.json and bash-guard defaulting
            # to off (in its own index.ts - the --bash-guard-disabled flag did not
            # take reliably in pi 0.80.2), that is a session with no prompts
            # (Nuno's call, 2026-08-25). /bash-guard inside pi arms the floor for
            # that session; PI_BASH_GUARD=on starts a session armed.
            if ($__pi) {
                $__piArgs = @('-a')
                # Provider and model are separate flags on purpose; see header.
                if ($__provider) { $__piArgs += @('--provider', $__provider) }
                if ($__model)    { $__piArgs += @('--model', $__model) }
                if ($__agent) {
                    $__af = Join-Path $HOME ".claude\agents\$__agent.md"
                    if (Test-Path $__af) { $__piArgs += @('--append-system-prompt', $__af) }
                    else { Write-Warning "M2_AUTOSTART_AGENT=$__agent but $__af is missing" }
                }
                # Read-only reviewer pane: no mutation or command execution.
                if ($__readonly) { $__piArgs += @('--exclude-tools', 'write,edit,bash,powershell') }
                & $__pi @__piArgs
            }
            else { Write-Warning 'autostart wanted pi, but pi is not on PATH' }
        }
        'claude' {
            # Resolves to the wrapper function from claude-wrapper.ps1 when the
            # profile defined one, so the session still gets the shared
            # system-prompt append.
            if (Get-Command claude -ErrorAction SilentlyContinue) { claude }
            else { Write-Warning 'autostart wanted claude, but claude is not on PATH' }
        }
        'glm' {
            $__glm = Join-Path $HOME '.claude\scripts\glm.ps1'

            # Optional: which agent definition becomes the session's system
            # prompt. herdr-build.ps1 sets this to 'builder'.
            $__agent = $env:M2_AUTOSTART_AGENT
            Remove-Item Env:\M2_AUTOSTART_AGENT -ErrorAction SilentlyContinue

            if (-not (Test-Path $__glm)) { Write-Warning "M2_AUTOSTART=glm but $__glm is missing" }
            elseif ($__agent) { & $__glm -Agent $__agent }
            else { & $__glm }
        }
        default { Write-Warning "Unknown M2_AUTOSTART value: $__autostart" }
    }
}
