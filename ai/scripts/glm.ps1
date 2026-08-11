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
    [string]$Model = "glm-5.2",
    [string]$PermissionMode = "acceptEdits",
    [string[]]$AllowedTools,
    [string]$OutputFormat,
    [int]$ContextTokens = 1000000,
    [switch]$WhatIfEnv
)

$ErrorActionPreference = 'Stop'

# A shell opened before the key was set will not have it in its process
# environment. Fall back to user scope rather than failing for no reason.
$key = $env:ZAI_API_KEY
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('ZAI_API_KEY', 'User') }
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('ZAI_API_KEY', 'Machine') }
if (-not $key) {
    throw "ZAI_API_KEY is not set. See $HOME\.claude\scripts\README-glm.md"
}

$env:ANTHROPIC_BASE_URL             = "https://api.z.ai/api/anthropic"
$env:ANTHROPIC_AUTH_TOKEN           = $key
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = "GLM-4.7"
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = "GLM-5.2"
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = "GLM-5.2"

# If an Anthropic key is present it can win over ANTHROPIC_AUTH_TOKEN and send
# the request to Anthropic, on Anthropic's bill, silently. Drop it.
if (Test-Path Env:\ANTHROPIC_API_KEY) { Remove-Item Env:\ANTHROPIC_API_KEY }

# Claude Code does not know GLM's window, so without this it assumes 200k and
# auto-compacts a session that had 800k of room left. z.ai documents GLM-5.2 at
# 1M input / 128k output.
$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$ContextTokens"

# Read by statusline-rich.ps1 to badge the session.
$env:M2_VENDOR = "glm"

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
