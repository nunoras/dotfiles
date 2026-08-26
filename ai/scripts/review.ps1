# Independent code review by the reviewer model, in a pane split to the right of
# the builder it reviews.
#
#   .\review.ps1 -Ticket path\to\ticket.md -Verdict "npm test -> PASS"
#   .\review.ps1 -Ticket t.md -Verdict "..." -BuilderPane <id>   # explicit pane
#   .\review.ps1 -Ticket t.md -Verdict "..." -DryRun             # plan only
#
# The pi successor to gpt-review.ps1. Same discipline: the reviewer runs
# read-only, on a different vendor to whoever wrote the code, and the review is
# relayed VERBATIM - this script sets the review up, it does not soften it.
#
# Reviewer model comes from the roster's 'reviewer' role, not the builder
# ticket. If the primary provider is not authenticated (openai-codex is not yet
# - see ticket 02), it falls back to the roster fallback and says so.
#
# -Verdict is a precondition, not an option: the reviewer cannot run anything, so
# without the human's build verdict it reviews around the hole. Keep PowerShell
# 5.1 compatible: no ??, no ?., no ternary.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Ticket,
    [string]$Verdict = "",
    [string]$Repo = (Get-Location).Path,   # the builder's worktree
    [string]$BuilderPane,                  # override; else resolved from the ticket
    [string]$BuilderAgent,                 # override; else disp-<slug>
    [string]$Model,                        # override the roster reviewer model
    [switch]$DryRun,
    [switch]$NoWatch,
    [int]$MaxDiffBytes = 400000,
    [int]$TimeoutMs = 1800000
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'roster.ps1')

# --- verdict is a precondition ----------------------------------------------
# Checked by hand, not [Parameter(Mandatory)], so a non-interactive run fails
# fast instead of hanging on a prompt.
$Verdict = $Verdict.Trim()
if (-not $Verdict) {
    throw @"
-Verdict is required.

The reviewer cannot run anything, so without the verdict it reviews around the
hole. You have already run the verify commands for the paths this diff touches.
Hand over what they said, one line per command:

  -Verdict "pwsh -File scripts\build.ps1 -> PASS"

If a command could not be run, say so rather than dropping the row:

  -Verdict "npm test -> not run: no live stack"

Never write PASS for something you did not watch pass.
"@
}
if ($Verdict -notmatch '(?im)\b(PASS|FAIL|not\s+run)\b') {
    throw "-Verdict does not state an outcome. Each line needs PASS, FAIL, or 'not run: <why>'. Got: $Verdict"
}

# --- ticket brief + base ----------------------------------------------------
function Read-TicketFrontmatter {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "ticket not found: $Path" }
    $lines = Get-Content $Path
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') { throw "ticket $Path has no frontmatter" }
    $fm = @{}; $i = 1; $closed = $false
    while ($i -lt $lines.Count) {
        if ($lines[$i].Trim() -eq '---') { $closed = $true; break }
        $c = $lines[$i].IndexOf(':')
        if ($c -ge 1) { $fm[$lines[$i].Substring(0,$c).Trim()] = $lines[$i].Substring($c+1).Trim().Trim('"').Trim("'") }
        $i++
    }
    if (-not $closed) { throw "ticket $Path frontmatter not closed" }
    $body = ($lines[($i+1)..($lines.Count-1)] -join "`n").Trim()
    return [pscustomobject]@{ Frontmatter = $fm; Body = $body }
}

$parsed = Read-TicketFrontmatter -Path $Ticket
$base = $parsed.Frontmatter['base']; if (-not $base) { $base = 'main' }
$slug = (([IO.Path]::GetFileNameWithoutExtension($Ticket)) -replace '[^\w\-]', '-').Trim('-').ToLower()
if (-not $BuilderAgent) { $BuilderAgent = "disp-$slug" }
$reviewerName = "review-$slug"

# --- reviewer model, with an auth-aware fallback ----------------------------
function Test-ProviderReady {
    param([string]$Provider)
    $raw = pi auth check --provider $Provider --no-refresh --json 2>&1 | Out-String
    try { $j = $raw | ConvertFrom-Json } catch { return $false }
    return ($j.status -eq 'ready')
}

if ($Model) {
    $modelRef = Split-ModelRef $Model
    $modelWhy = "override"
} else {
    $entry = Get-RosterEntry -Role 'reviewer'
    $primary = Split-ModelRef $entry.Primary
    if (Test-ProviderReady $primary.Provider) {
        $modelRef = $primary; $modelWhy = "roster primary"
    } elseif ($entry.Fallback) {
        $modelRef = Split-ModelRef $entry.Fallback
        $modelWhy = "roster fallback ($($primary.Provider) not authenticated)"
        Write-Host "Reviewer primary provider '$($primary.Provider)' is not ready; using fallback $($entry.Fallback)." -ForegroundColor Yellow
    } else {
        throw @"
The reviewer has no reachable model.

Primary is $($entry.Primary) and provider '$($primary.Provider)' is not ready.
There is no roster fallback on purpose: every GPT id on OpenRouter is paid, and
this account is free-tier only, so an OpenRouter fallback would die on a 402
mid-review instead of failing here.

Either authenticate the primary provider, or fall back the way AGENTS.md
describes - run the Opus 'reviewer' agent by hand, and say in the report that
the review ran on the fallback and why.

To review on some other model deliberately, pass -Model <provider:id>.
"@
    }
}

# --- collect the change (same shape gpt-review.ps1 feeds) -------------------
if (-not (Test-Path (Join-Path $Repo '.git'))) {
    git -C $Repo rev-parse --git-dir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Repo is not a git repository." }
}
$range = "$base...HEAD"
$diff = (git -C $Repo diff $range) -join "`n"
$stat = (git -C $Repo diff --stat $range) -join "`n"
$log  = (git -C $Repo log --oneline "$base..HEAD") -join "`n"
if (-not $diff) { Write-Host "No changes to review ($range). Did the builder commit?" -ForegroundColor Yellow; return }
$truncated = $false
if ($diff.Length -gt $MaxDiffBytes) { $diff = $diff.Substring(0, $MaxDiffBytes); $truncated = $true }

# --- build the review task file ---------------------------------------------
# Written to temp (not the worktree, which stays clean for the read-only
# reviewer). The reviewer's standards come from reviewer.md as its system prompt
# (appended by autostart via M2_AUTOSTART_AGENT=reviewer), so the task file only
# carries the intent, the verdict, and the change.
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# The change under review")
[void]$sb.AppendLine(); [void]$sb.AppendLine("Range: $range"); [void]$sb.AppendLine("Repository root: $Repo"); [void]$sb.AppendLine()
[void]$sb.AppendLine("## What it was supposed to do"); [void]$sb.AppendLine()
[void]$sb.AppendLine($parsed.Body); [void]$sb.AppendLine()
[void]$sb.AppendLine("Treat this as the intent to review against. If the diff does less than this, or more, that is a finding."); [void]$sb.AppendLine()
[void]$sb.AppendLine("## Build verdict"); [void]$sb.AppendLine()
[void]$sb.AppendLine("These commands were run against this exact change by the party dispatching this review, not by you:"); [void]$sb.AppendLine()
[void]$sb.AppendLine('```'); [void]$sb.AppendLine($Verdict); [void]$sb.AppendLine('```'); [void]$sb.AppendLine()
[void]$sb.AppendLine("Treat this as given. You cannot execute anything, so do not report a missing test or lint verdict as a finding. Spend the effort on what a passing build cannot see: correctness, edge cases, whether the diff matches the intent, and what it broke where the verify command does not reach."); [void]$sb.AppendLine()
if ($log) { [void]$sb.AppendLine("## Commits"); [void]$sb.AppendLine('```'); [void]$sb.AppendLine($log); [void]$sb.AppendLine('```'); [void]$sb.AppendLine() }
[void]$sb.AppendLine("## Files touched"); [void]$sb.AppendLine('```'); [void]$sb.AppendLine($stat); [void]$sb.AppendLine('```'); [void]$sb.AppendLine()
[void]$sb.AppendLine("## Diff"); [void]$sb.AppendLine('```diff'); [void]$sb.AppendLine($diff); [void]$sb.AppendLine('```')
if ($truncated) { [void]$sb.AppendLine(); [void]$sb.AppendLine("NOTE: diff truncated at $MaxDiffBytes bytes. Read the remaining files directly and say so.") }
[void]$sb.AppendLine(); [void]$sb.AppendLine("You have read-only access to the repository at $Repo. Read the surrounding code, callers, and tests; most bugs are not visible in the changed lines alone. You did not write this and have not seen the reasoning - do not assume it is correct. Produce the report in the format your instructions define, and nothing else.")

$taskFile = Join-Path ([IO.Path]::GetTempPath()) "review-task-$slug.md"
Set-Content -Path $taskFile -Value $sb.ToString() -Encoding utf8

$plan = [pscustomobject]@{
    Ticket = $Ticket; Reviewer = $reviewerName; BuilderAgent = $BuilderAgent
    Provider = $modelRef.Provider; Model = $modelRef.Model; ModelChoice = $modelWhy
    Range = $range; DiffChars = $diff.Length; Truncated = $truncated; TaskFile = $taskFile; Repo = $Repo
}
Write-Host "Review plan:" -ForegroundColor Cyan
$plan | Format-List | Out-String | Write-Host

if ($DryRun) {
    Write-Host "DryRun: would split the builder pane right and run" -ForegroundColor Green
    Write-Host "  pi -a --provider $($modelRef.Provider) --model $($modelRef.Model) --append-system-prompt <reviewer.md> --exclude-tools write,edit,bash,powershell" -ForegroundColor Green
    Write-Host "  then point it at $taskFile. Relay the review verbatim." -ForegroundColor Green
    return $plan
}

# --- herdr plumbing ---------------------------------------------------------
function Invoke-Herdr {
    param([string[]]$HerdrArgs)
    $raw = & herdr @HerdrArgs 2>&1 | Out-String
    try { $json = $raw | ConvertFrom-Json } catch { throw "herdr $($HerdrArgs -join ' ') returned non-JSON: $raw" }
    if ($json.error) { throw "herdr $($HerdrArgs[0]) $($HerdrArgs[1]): $($json.error.message)" }
    return $json.result
}
function Wait-Agent {
    param([string]$Name, [int]$TimeoutMs = 1800000, [int]$PollMs = 2000)
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs); $sawWorking = $false; $settled = @('idle','done','blocked')
    while ((Get-Date) -lt $deadline) {
        $status = (Invoke-Herdr @('agent','get',$Name)).agent.agent_status
        if ($status -eq 'working') { $sawWorking = $true }
        elseif ($status -eq 'blocked') { return 'blocked' }
        elseif ($sawWorking -and $settled -contains $status) { return $status }
        Start-Sleep -Milliseconds $PollMs
    }
    return 'timeout'
}

if (-not (Get-Command herdr -ErrorAction SilentlyContinue)) { throw "herdr not found." }

# Resolve the builder's pane to split beside it. Prefer the explicit -BuilderPane;
# otherwise ask herdr for the agent and read a pane id off it defensively.
if (-not $BuilderPane) {
    $a = $null
    try { $a = (Invoke-Herdr @('agent','get',$BuilderAgent)).agent } catch {}
    if ($a) {
        foreach ($f in 'pane_id','pane','paneId') { if ($a.$f) { $BuilderPane = $a.$f; break } }
    }
}
if (-not $BuilderPane) {
    throw "could not resolve the builder pane for agent '$BuilderAgent'. Pass -BuilderPane <id> (see 'herdr pane list')."
}

# Split right: builder stays on the left, reviewer opens on the right.
$pane = (Invoke-Herdr @('pane','split',$BuilderPane,'--direction','right',
        '--cwd',$Repo,
        '--env','M2_AUTOSTART=pi',
        '--env',"M2_PROVIDER=$($modelRef.Provider)",
        '--env',"M2_MODEL=$($modelRef.Model)",
        '--env','M2_AUTOSTART_AGENT=reviewer',
        '--env','M2_READONLY=1',
        '--no-focus')).pane
$paneId = $pane.pane_id
Write-Host "Reviewer pane $paneId opening (right of builder), waiting for the agent..." -ForegroundColor Cyan

$detectDeadline = (Get-Date).AddSeconds(90); $detected = $false
while ((Get-Date) -lt $detectDeadline) {
    $p = (Invoke-Herdr @('pane','get',$paneId)).pane
    if ($p.agent) { $detected = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $detected) { throw "no reviewer agent detected in $paneId after 90s. Check herdr-autostart.ps1 is dot-sourced by the PowerShell 5.1 profile." }
Invoke-Herdr @('agent','rename',$paneId,$reviewerName) | Out-Null
Write-Host "Reviewer '$reviewerName' up on $($modelRef.Provider):$($modelRef.Model) ($modelWhy)" -ForegroundColor Green

Invoke-Herdr @('agent','prompt',$reviewerName,"Read the review task at $taskFile in full, then review the repository in this worktree. You are read-only: do not modify anything.") | Out-Null
Write-Host "Review task submitted." -ForegroundColor Green

if ($NoWatch) {
    Write-Host ""; Write-Host "Not waiting. Read the review and RELAY IT VERBATIM:  herdr agent read $reviewerName" -ForegroundColor Yellow
    return $plan
}
$status = Wait-Agent -Name $reviewerName -TimeoutMs $TimeoutMs
Invoke-Herdr @('notification','show',"$reviewerName finished ($status)") | Out-Null
Write-Host ""; Write-Host "Reviewer $status." -ForegroundColor Green
Write-Host "Read it and RELAY VERBATIM - do not paraphrase, do not soften:" -ForegroundColor Yellow
Write-Host "  herdr agent read $reviewerName"
return $plan
