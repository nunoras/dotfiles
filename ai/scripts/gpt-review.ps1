# Independent code review by GPT, via the Codex CLI.
#
#   .\gpt-review.ps1 -Context "ticket #42: strip punctuation from slugs"
#   .\gpt-review.ps1 -Base main -Context "..." -OutFile review.md
#
# The reviewer runs read-only and on a different vendor to whoever wrote the
# code. That independence is the entire point, so this script does not filter,
# summarise or soften what comes back. Callers must relay it verbatim.
#
# The reviewing standards come from ~/.claude/agents/reviewer.md, so there is one
# definition of "a good review" whether it runs on Claude or on GPT.

[CmdletBinding()]
param(
    [string]$Base,
    [string]$Context = "",
    [string]$Cwd = (Get-Location).Path,
    [string]$Model = "gpt-5.5",
    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$Effort = "xhigh",
    [string]$OutFile,
    [int]$MaxDiffBytes = 400000
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    throw "codex CLI not found. Install it, or run the review on the Claude-side 'reviewer' agent instead."
}
if (-not (Test-Path (Join-Path $Cwd '.git'))) {
    # A worktree has .git as a file, not a directory, so Test-Path still holds.
    git -C $Cwd rev-parse --git-dir *> $null
    if ($LASTEXITCODE -ne 0) { throw "$Cwd is not a git repository." }
}

# --- collect the change -----------------------------------------------------
if ($Base) {
    $range = "$Base...HEAD"
    $diff = git -C $Cwd diff $range
    $stat = git -C $Cwd diff --stat $range
    $log = git -C $Cwd log --oneline "$Base..HEAD"
}
else {
    $range = "working tree vs HEAD"
    $diff = git -C $Cwd diff HEAD
    $stat = git -C $Cwd diff --stat HEAD
    $log = ""
}

if (-not $diff) { Write-Output "No changes to review ($range)."; return }

$truncated = $false
if ($diff.Length -gt $MaxDiffBytes) {
    $diff = $diff.Substring(0, $MaxDiffBytes)
    $truncated = $true
}

# --- reviewer standards, from the agent definition --------------------------
$reviewerDef = "$HOME\.claude\agents\reviewer.md"
$standards = ""
if (Test-Path $reviewerDef) {
    $lines = Get-Content $reviewerDef
    # Drop the YAML frontmatter; it is Claude Code plumbing, not review guidance.
    $fence = ($lines | Select-String -Pattern '^---\s*$' | Select-Object -First 2 | ForEach-Object LineNumber)
    if ($fence.Count -ge 2) { $standards = ($lines | Select-Object -Skip $fence[1]) -join "`n" }
    else { $standards = $lines -join "`n" }
}

# --- build the prompt -------------------------------------------------------
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine($standards)
[void]$sb.AppendLine()
[void]$sb.AppendLine("---")
[void]$sb.AppendLine()
[void]$sb.AppendLine("# The change under review")
[void]$sb.AppendLine()
[void]$sb.AppendLine("Range: $range")
[void]$sb.AppendLine("Repository root: $Cwd")
[void]$sb.AppendLine()
if ($Context) {
    [void]$sb.AppendLine("## What it was supposed to do")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($Context)
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Treat this as the intent to review against. If the diff does less than this, or more, that is a finding.")
}
else {
    [void]$sb.AppendLine("No ticket or brief was supplied. Review for correctness only, and say so in the report rather than inventing an intent.")
}
[void]$sb.AppendLine()
if ($log) {
    [void]$sb.AppendLine("## Commits")
    [void]$sb.AppendLine('```'); [void]$sb.AppendLine($log); [void]$sb.AppendLine('```')
}
[void]$sb.AppendLine("## Files touched")
[void]$sb.AppendLine('```'); [void]$sb.AppendLine($stat); [void]$sb.AppendLine('```')
[void]$sb.AppendLine()
[void]$sb.AppendLine("## Diff")
[void]$sb.AppendLine('```diff')
[void]$sb.AppendLine($diff)
[void]$sb.AppendLine('```')
if ($truncated) {
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("NOTE: the diff was truncated at $MaxDiffBytes bytes. Read the remaining files directly and say in your report that you did.")
}
[void]$sb.AppendLine()
[void]$sb.AppendLine("You have read-only access to the whole repository at $Cwd. Read the surrounding code, the callers, and the tests. Most real bugs are not visible in the changed lines alone.")
[void]$sb.AppendLine("You did not write this code and have not seen the reasoning behind it. Do not assume it is correct.")
[void]$sb.AppendLine("Produce the report in the format defined above, and nothing else.")

$promptFile = Join-Path ([System.IO.Path]::GetTempPath()) "gpt-review-prompt-$PID.md"
$answerFile = Join-Path ([System.IO.Path]::GetTempPath()) "gpt-review-answer-$PID.md"
Set-Content -Path $promptFile -Value $sb.ToString() -Encoding utf8

try {
    $env:CODEX_QUIET_MODE = "1"
    & codex exec `
        -m $Model `
        -c "model_reasoning_effort=`"$Effort`"" `
        -s read-only `
        -C $Cwd `
        --ephemeral `
        -o $answerFile `
        (Get-Content $promptFile -Raw) *> $null

    if (-not (Test-Path $answerFile)) { throw "codex produced no review (exit $LASTEXITCODE)." }
    $review = Get-Content $answerFile -Raw

    if ($OutFile) { Set-Content -Path $OutFile -Value $review -Encoding utf8 }
    Write-Output $review
}
finally {
    Remove-Item $promptFile, $answerFile -ErrorAction SilentlyContinue
}
