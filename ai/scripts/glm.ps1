# Run Claude Code against Z.AI's GLM models instead of Anthropic's.
#
#   .\glm.ps1                       interactive GLM session
#   .\glm.ps1 -Prompt "do the thing"   headless, one shot, for shell-outs
#
# Nothing here touches your normal `claude`. The env is set on this process only,
# so an Anthropic session in another terminal is unaffected.
#
# Requires ZAI_API_KEY. Set it once, at user scope:
#   [Environment]::SetEnvironmentVariable('ZAI_API_KEY','<key>','User')

[CmdletBinding()]
param(
    [string]$Prompt,
    [string]$Agent,
    # An alias, not a raw GLM name. Claude Code validates --model against its
    # own aliases and hard-fails an unknown string with unrecognized_model and
    # exit 1, which is what "glm-5.2" here did. "sonnet" is recognised, and
    # glm-env.ps1's ANTHROPIC_DEFAULT_SONNET_MODEL maps it to GLM-5.2 - the
    # mapping README-glm.md already documents.
    [string]$Model = "sonnet",
    [string]$PermissionMode = "acceptEdits",
    [string[]]$AllowedTools,
    [string]$OutputFormat,
    [int]$ContextTokens = 1000000,
    [switch]$WhatIfEnv
)

$ErrorActionPreference = 'Stop'

# A shell opened before the key was set will not have it in its process
# environment, which is why glm-env.ps1 falls back to user scope.
#
# The environment lives in glm-env.ps1 so that this script and the herdr pane
# flow cannot drift apart on what a GLM session actually is.
. (Join-Path $PSScriptRoot 'glm-env.ps1') -ContextTokens $ContextTokens
$key = $env:ANTHROPIC_AUTH_TOKEN

if ($WhatIfEnv) {
    [pscustomobject]@{
        BaseUrl        = $env:ANTHROPIC_BASE_URL
        TokenLength    = $key.Length
        TokenPrefix    = $key.Substring(0, [Math]::Min(4, $key.Length))
        AnthropicKeyIn = (Test-Path Env:\ANTHROPIC_API_KEY)
        Model          = $Model
    } | Format-List
    return
}

$claudeArgs = @('--model', $Model)

# --agent makes that agent's definition the system prompt of the session itself,
# so ~/.claude/agents/builder.md governs the GLM run without being restated in
# the prompt. --model still wins over the agent's own `model:` field.
if ($Agent) { $claudeArgs += @('--agent', $Agent) }

if ($Prompt) {
    $claudeArgs += @('-p', $Prompt, '--permission-mode', $PermissionMode)

    # acceptEdits covers file writes but NOT running a test suite, so without
    # this a headless builder edits code it cannot verify and says so. Passing
    # Bash here is what makes the role able to do its job.
    if ($AllowedTools) { $claudeArgs += @('--allowedTools', ($AllowedTools -join ',')) }

    if ($OutputFormat) { $claudeArgs += @('--output-format', $OutputFormat) }
}

& claude @claudeArgs
exit $LASTEXITCODE
