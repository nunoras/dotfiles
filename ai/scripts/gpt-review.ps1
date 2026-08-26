# Independent code review by GPT, via the Codex CLI.
#
#   .\gpt-review.ps1 -Context "ticket #42: ..." -BuildVerdict "npm test -> PASS"
#   .\gpt-review.ps1 -Base main -Context "..." -BuildVerdict "..." -OutFile review.md
#
# The reviewer runs read-only and on a different vendor to whoever wrote the
# code. That independence is the entire point, so this script does not filter,
# summarise or soften what comes back. Callers must relay it verbatim.
#
# The reviewing standards come from ~/.claude/agents/reviewer.md, so there is one
# definition of "a good review" whether it runs on Claude or on GPT.
#
# -BuildVerdict is required, and that is deliberate. GPT cannot execute anything
# here - the Codex sandbox on this machine has no working sandbox binary - so
# left to itself it reports "no compiler verdict" and reviews around the hole.
# The caller has already run the verify commands; the only thing that ever went
# wrong was forgetting to say so. Making it a parameter turns that from a habit
# into a precondition. The script does not know any repo's verify table and
# should not: that lives in each repo's CLAUDE.md, and the caller looks it up.

[CmdletBinding()]
param(
    [string]$Base,
    [string]$Context = "",

    # One line per verify command, as "<command>  ->  PASS" / "-> FAIL", or
    # "<command>  ->  not run: <why>". A stated gap is usable; a missing one is
    # not, which is why silence is the one thing this will not accept.
    [string]$BuildVerdict = "",

    [string]$Cwd = (Get-Location).Path,
    [string]$Model = "gpt-5.5",
    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$Effort = "xhigh",
    [string]$OutFile,
    [int]$MaxDiffBytes = 400000
)

$ErrorActionPreference = 'Stop'

# --- the build verdict is a precondition, not an option ---------------------
# Checked by hand rather than with [Parameter(Mandatory)], because a mandatory
# parameter *prompts* when it is missing, and this script is mostly run by an
# agent from a non-interactive shell. That would hang the dispatch instead of
# failing it, which is a worse version of the problem.
$BuildVerdict = $BuildVerdict.Trim()
if (-not $BuildVerdict) {
    throw @"
-BuildVerdict is required.

GPT cannot run anything on this machine, so without the verdict it reports "no
compiler verdict" and reviews around the hole. You have already run the verify
commands for the paths this diff touches - look them up in the repo's CLAUDE.md
verify table if you have not. Hand over what they said:

  -BuildVerdict "pwsh -File scripts\freebsd-vm\17-build-cpp.ps1 -Base main  ->  PASS"

One line per command. If a command could not be run, say so rather than
dropping the row:

  -BuildVerdict "npm --prefix apps/launcher test  ->  not run: no live stack"

Never write PASS for something you did not watch pass.
"@
}
if ($BuildVerdict -notmatch '(?im)\b(PASS|FAIL|not\s+run)\b') {
    throw "-BuildVerdict does not state an outcome. Each line needs PASS, FAIL, or 'not run: <why>'. Got: $BuildVerdict"
}

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    throw "codex CLI not found. Install it, or run the review on the Claude-side 'reviewer' agent instead."
}
if (-not (Test-Path (Join-Path $Cwd '.git'))) {
    # A worktree has .git as a file, not a directory, so Test-Path still holds.
    git -C $Cwd rev-parse --git-dir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Cwd is not a git repository." }
}

# --- collect the change -----------------------------------------------------
# Join every one of these into a single string. `git` returns String[], and
# StringBuilder.AppendLine(Object) stringifies an array by joining it with
# *spaces* - which silently handed GPT a diff with no line structure at all,
# hunk headers and context welded onto the lines they belong to. It also made
# $diff.Length a line count, so the -MaxDiffBytes guard below measured the wrong
# thing and its .Substring() would have thrown on the array it was guarding.
if ($Base) {
    $range = "$Base...HEAD"
    $diff = (git -C $Cwd diff $range) -join "`n"
    $stat = (git -C $Cwd diff --stat $range) -join "`n"
    $log = (git -C $Cwd log --oneline "$Base..HEAD") -join "`n"
}
else {
    $range = "working tree vs HEAD"
    $diff = (git -C $Cwd diff HEAD) -join "`n"
    $stat = (git -C $Cwd diff --stat HEAD) -join "`n"
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
[void]$sb.AppendLine("## Build verdict")
[void]$sb.AppendLine()
[void]$sb.AppendLine("These commands were run against this exact change, in the working tree it was built in, by the party dispatching this review - not by you:")
[void]$sb.AppendLine()
[void]$sb.AppendLine('```'); [void]$sb.AppendLine($BuildVerdict); [void]$sb.AppendLine('```')
[void]$sb.AppendLine()
[void]$sb.AppendLine("Treat this as given. You cannot execute anything in this sandbox, so do not report a missing compiler, test or lint verdict as a finding, and do not caveat your report on not having one.")
[void]$sb.AppendLine("Spend the effort on what a passing build cannot see: correctness, edge cases, whether the diff matches the intent above, and what it broke somewhere the verify command does not reach.")
[void]$sb.AppendLine("A FAIL or a 'not run' row is itself information - say what you think caused it, or what the unrun check would have covered.")
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
    # The prompt goes in on stdin as `-`, not as an argument, and the transcript
    # is swallowed with a pipeline rather than `*> $null`. Both matter:
    #   - `*> $null` makes PowerShell 7.4+ redirect every stream through
    #     ProcessStartInfo, which then throws "StandardOutputEncoding is only
    #     supported when standard output is redirected" before codex ever runs.
    #   - with the prompt as an argument and stdin a non-tty pipe, codex appends
    #     stdin as a <stdin> block and blocks on "Reading additional input from
    #     stdin..." forever. Feeding the prompt in and letting the pipe close is
    #     what ends the read.
    # The review itself comes back through -o $answerFile, not through stdout,
    # so nothing is lost by discarding the transcript.
    Get-Content $promptFile -Raw | & codex exec `
        -m $Model `
        -c "model_reasoning_effort=`"$Effort`"" `
        -s read-only `
        -C $Cwd `
        --ephemeral `
        -o $answerFile `
        - 2>&1 | Out-Null

    if (-not (Test-Path $answerFile)) { throw "codex produced no review (exit $LASTEXITCODE)." }
    $review = Get-Content $answerFile -Raw

    if ($OutFile) { Set-Content -Path $OutFile -Value $review -Encoding utf8 }
    Write-Output $review
}
finally {
    Remove-Item $promptFile, $answerFile -ErrorAction SilentlyContinue
}
