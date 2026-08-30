# Point the current PowerShell session at Z.AI's GLM models.
#
# Dot-source it, do not run it - it has to mutate the caller's environment:
#
#   . "$HOME\.claude\scripts\glm-env.ps1"
#   claude          # now talks to GLM
#
# `glm.ps1` dot-sources this too, so the headless path and any terminal path
# share one definition of "what makes a session a GLM session".
#
# The key is read here rather than passed in, so it never appears in a command
# line, a launcher --env argument, or a process listing.

param(
    [int]$ContextTokens = 1000000
)

$key = $env:ZAI_API_KEY
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('ZAI_API_KEY', 'User') }
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('ZAI_API_KEY', 'Machine') }
if (-not $key) {
    throw "ZAI_API_KEY is not set. See $HOME\.claude\scripts\README-glm.md"
}

$env:ZAI_API_KEY                    = $key
$env:ANTHROPIC_BASE_URL             = "https://api.z.ai/api/anthropic"
$env:ANTHROPIC_AUTH_TOKEN           = $key
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = "GLM-4.7"
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = "GLM-5.2"
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = "GLM-5.2"

# Claude Code does not know GLM's window and would otherwise assume 200k,
# compacting a session that had 800k of room left. Z.AI documents 1M input.
$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$ContextTokens"

# An Anthropic key outranks ANTHROPIC_AUTH_TOKEN and would silently send the
# request to Anthropic, on Anthropic's bill.
if (Test-Path Env:\ANTHROPIC_API_KEY) { Remove-Item Env:\ANTHROPIC_API_KEY }

# Read by statusline-rich.ps1 to badge the session.
$env:M2_VENDOR = "glm"
