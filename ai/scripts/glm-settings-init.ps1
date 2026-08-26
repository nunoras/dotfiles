# Generate ~/.claude/glm-settings.local.json from $ZAI_API_KEY.
#
# Run once, by hand:
#   pwsh -File "$HOME\.claude\scripts\glm-settings-init.ps1"
#
# Why this file exists: `herdr agent start --kind claude` launches claude in a
# pane and gives no way to set environment variables for it. The alternative is
# `herdr pane split --env ANTHROPIC_AUTH_TOKEN=<key>`, which puts the key on a
# command line and into herdr's socket API call. A settings file keeps it on
# disk instead, readable only by you, and `claude --settings <file>` picks it up.
#
# The generated file holds a live credential. It is written outside the dotfiles
# repo on purpose, and must never be committed or copied into one.

[CmdletBinding()]
param(
    [string]$Path = "$HOME\.claude\glm-settings.local.json",
    [int]$ContextTokens = 1000000
)

$ErrorActionPreference = 'Stop'

$key = $env:ZAI_API_KEY
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('ZAI_API_KEY', 'User') }
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('ZAI_API_KEY', 'Machine') }
if (-not $key) {
    throw "ZAI_API_KEY is not set. See $HOME\.claude\scripts\README-glm.md"
}

$cfg = [ordered]@{
    env = [ordered]@{
        ANTHROPIC_BASE_URL             = "https://api.z.ai/api/anthropic"
        ANTHROPIC_AUTH_TOKEN           = $key
        ANTHROPIC_DEFAULT_HAIKU_MODEL  = "GLM-4.7"
        ANTHROPIC_DEFAULT_SONNET_MODEL = "GLM-5.2"
        ANTHROPIC_DEFAULT_OPUS_MODEL   = "GLM-5.2"
        CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$ContextTokens"
        M2_VENDOR                      = "glm"
    }
}

$cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding utf8

# Owner-only ACL. The key is already a user-scope env var, so this is not a new
# secret, but a file on disk outlives a process environment and deserves it.
try {
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$env:USERDOMAIN\$env:USERNAME", 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $Path -AclObject $acl
    $acled = $true
}
catch { $acled = $false }

Write-Output "Wrote $Path"
Write-Output "  keys: $(($cfg.env.Keys) -join ', ')"
Write-Output "  token: $($key.Length) chars, prefix $($key.Substring(0,4))..."
Write-Output "  owner-only ACL: $acled"
Write-Output ""
Write-Output "Verify with:"
Write-Output "  claude -p 'name your model, nothing else' --settings `"$Path`" --model glm-5.2"
