# SessionStart hook: preload the unslop skill into every session.
#
# Plain stdout from a SessionStart hook becomes context the agent can see, so
# printing the skill body here removes the need for the model to invoke it.
# The skill stays invocable as /unslop.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

# Not $PSScriptRoot: this file is symlinked into ~/.claude/hooks, and resolving
# a sibling directory from a symlink is unreliable. The skill lives at a fixed path.
$skill = Join-Path $HOME '.claude\skills\unslop\SKILL.md'
if (-not (Test-Path -LiteralPath $skill)) { exit 0 }

$lines = Get-Content -LiteralPath $skill -Encoding UTF8

# Drop the YAML frontmatter. Its name and description already reach the model
# through the skill listing, so repeating them here only costs tokens.
$body = $lines
if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $end = $i; break }
    }
    if ($end -ge 0) { $body = $lines[($end + 1)..($lines.Count - 1)] }
}

Write-Output 'The unslop skill is preloaded below. Apply it to everything written for a human'
Write-Output 'to read, including chat replies. It does not apply to code or code comments.'
Write-Output ''
Write-Output ($body -join "`n").Trim()
