# Put the same system-prompt append on every Claude Code session.
#
# Claude Code has no settings.json key and no env var for this. Verified on
# 2.x: a `appendSystemPrompt` key passed via --settings is silently ignored,
# and the binary contains no CLAUDE_CODE_APPEND_SYSTEM_PROMPT. The only
# mechanism is the --append-system-prompt-file flag, which means the flag has
# to be present at every launch - hence this shim.
#
# Dot-sourced from the PowerShell profile, because Windows
# PowerShell 5.1 for its panes rather than pwsh 7, and those read different
# profile paths. Keep this file 5.1 compatible: no ??, no ?., no ternary.
#
# Escape hatches:
#   $env:M2_NO_PROMPT_APPEND = 1   -> this shell launches plain claude
#   claude.cmd ...                 -> bypasses the function entirely
#   any --system-prompt* flag      -> the shim steps aside, you win

$__claudeAppendFile = Join-Path $HOME '.claude\system-prompt-append.md'

# Resolve the real executable once, at profile load.
# -CommandType Application skips the function we are about to define, and we
# prefer .cmd/.exe over the extensionless /bin/sh shim npm also drops here.
$__claudeExe = $null
$__claudeCandidates = @(Get-Command 'claude' -CommandType Application -All -ErrorAction SilentlyContinue)
foreach ($__c in $__claudeCandidates) {
    if ($__c.Source -like '*.cmd' -or $__c.Source -like '*.exe') { $__claudeExe = $__c.Source; break }
}
if ((-not $__claudeExe) -and $__claudeCandidates.Count -gt 0) { $__claudeExe = $__claudeCandidates[0].Source }

if ($__claudeExe) {
    function claude {
        $callArgs = @($args)
        $skip = $false

        if ($env:M2_NO_PROMPT_APPEND) { $skip = $true }
        if (-not (Test-Path $__claudeAppendFile)) { $skip = $true }

        # Caller is already steering the system prompt; do not fight them.
        foreach ($a in $callArgs) {
            if ($a -is [string] -and ($a -like '--system-prompt*' -or $a -like '--append-system-prompt*')) {
                $skip = $true
            }
        }

        if (-not $skip) {
            $callArgs = @('--append-system-prompt-file', $__claudeAppendFile) + $callArgs
        }

        & $__claudeExe @callArgs
    }
}
