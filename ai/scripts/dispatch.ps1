# Dispatch a ticket into a herdr pane on the harness its model implies.
#
#   .\dispatch.ps1 -Ticket path\to\ticket.md
#   .\dispatch.ps1 -Ticket ticket.md -DryRun      # show the plan, spawn nothing
#   .\dispatch.ps1 -Ticket ticket.md -NoWatch     # dispatch and return
#
# The generalized successor to herdr-build.ps1: instead of always GLM on Claude
# Code, it reads the ticket's frontmatter (role, model, fallbackModels, base),
# derives the harness from the model's provider (anthropic -> Claude Code,
# else -> pi), and opens the right session in a fresh worktree.
#
# Human-run, one ticket at a time - the spend gate is a person. `blocked` is
# recoverable in the pane. Keep PowerShell 5.1 compatible (herdr spawns 5.1):
# no ??, no ?., no ternary.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Ticket,   # path to the ticket .md
    [string]$Repo = (Get-Location).Path,
    [switch]$DryRun,
    [switch]$NoWatch,
    [int]$TimeoutMs = 1800000
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'roster.ps1')

# --- ticket parsing ---------------------------------------------------------
# Flat YAML frontmatter between the first two --- fences. One "key: value" per
# line; good enough for the fields tickets carry, without a YAML dependency.
function Read-TicketFrontmatter {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "ticket not found: $Path" }
    $lines = Get-Content $Path
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        throw "ticket $Path has no YAML frontmatter (first line must be '---')"
    }
    $fm = @{}
    $i = 1
    $closed = $false
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line.Trim() -eq '---') { $closed = $true; break }
        $c = $line.IndexOf(':')
        if ($c -ge 1) {
            $k = $line.Substring(0, $c).Trim()
            $v = $line.Substring($c + 1).Trim().Trim('"').Trim("'")
            $fm[$k] = $v
        }
        $i++
    }
    if (-not $closed) { throw "ticket $Path frontmatter is not closed by a second '---'" }
    $body = ($lines[($i + 1)..($lines.Count - 1)] -join "`n").Trim()
    return [pscustomobject]@{ Frontmatter = $fm; Body = $body }
}

# --- resolve the dispatch plan ----------------------------------------------
$parsed = Read-TicketFrontmatter -Path $Ticket
$fm = $parsed.Frontmatter

foreach ($req in 'role', 'model') {
    if (-not $fm[$req]) { throw "ticket $Ticket is missing required frontmatter '$req'" }
}

$role     = $fm['role']
$modelRef = Split-ModelRef $fm['model']
$harness  = Get-Harness -Provider $modelRef.Provider
$base     = $fm['base']; if (-not $base) { $base = 'main' }
$fallback = $fm['fallbackModels']   # may be empty; consumed by the watcher (ticket 05)

$slug   = ([IO.Path]::GetFileNameWithoutExtension($Ticket)) -replace '[^\w\-]', '-'
$slug   = $slug.Trim('-').ToLower()
$name   = "disp-$slug"
$branch = "ticket/$slug"

$plan = [pscustomobject]@{
    Ticket   = $Ticket
    Role     = $role
    Provider = $modelRef.Provider
    Model    = $modelRef.Model
    Harness  = $harness
    Fallback = $fallback
    Base     = $base
    Branch   = $branch
    Agent    = $name
    Repo     = $Repo
    BriefChars = $parsed.Body.Length
}

Write-Host "Dispatch plan:" -ForegroundColor Cyan
$plan | Format-List | Out-String | Write-Host

if ($harness -eq 'claude') {
    # Not exercised yet: the only Anthropic role is the planner, which runs as
    # an interactive Claude Code session, not something dispatch launches. Wire
    # the derivation but refuse to pretend the launch path works.
    Write-Host "Harness 'claude' is not implemented in dispatch yet." -ForegroundColor Yellow
    Write-Host "Anthropic roles (the planner) run as an interactive Claude Code session." -ForegroundColor Yellow
    Write-Host "Re-scope the ticket to a pi model, or launch Claude Code by hand." -ForegroundColor Yellow
    exit 2
}

if ($DryRun) {
    Write-Host "DryRun: would create worktree '$branch' off '$base', split a pane running" -ForegroundColor Green
    Write-Host "  pi -a --provider $($modelRef.Provider) --model $($modelRef.Model) --append-system-prompt <~/.claude/agents/$role.md>" -ForegroundColor Green
    Write-Host "  then submit the ticket brief and watch." -ForegroundColor Green
    return $plan
}

# --- herdr plumbing (mirrors herdr-build.ps1) -------------------------------
function Invoke-Herdr {
    param([string[]]$HerdrArgs)
    $raw = & herdr @HerdrArgs 2>&1 | Out-String
    try { $json = $raw | ConvertFrom-Json } catch { throw "herdr $($HerdrArgs -join ' ') returned non-JSON: $raw" }
    if ($json.error) { throw "herdr $($HerdrArgs[0]) $($HerdrArgs[1]): $($json.error.message)" }
    return $json.result
}

# Poll rather than `agent prompt --wait`: that matches the first state after
# submission, so it misses an agent that has not started working yet.
function Wait-Agent {
    param([string]$Name, [int]$TimeoutMs = 1800000, [int]$PollMs = 2000)
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $sawWorking = $false
    $settled = @('idle', 'done', 'blocked')
    while ((Get-Date) -lt $deadline) {
        $status = (Invoke-Herdr @('agent', 'get', $Name)).agent.agent_status
        if ($status -eq 'working') { $sawWorking = $true }
        elseif ($status -eq 'blocked') { return 'blocked' }
        elseif ($sawWorking -and $settled -contains $status) { return $status }
        Start-Sleep -Milliseconds $PollMs
    }
    return 'timeout'
}

if (-not (Get-Command herdr -ErrorAction SilentlyContinue)) { throw "herdr not found." }
if (-not (Test-Path "$HOME\.claude\scripts\herdr-autostart.ps1")) {
    throw "herdr-autostart.ps1 is missing; the pane would never start an agent."
}

# 1. isolated, visible worktree
Write-Host "Creating worktree $branch from $base..." -ForegroundColor Cyan
$wt = Invoke-Herdr @('worktree', 'create', '--cwd', $Repo, '--branch', $branch, '--base', $base, '--label', "dispatch $slug")
$wtPath = $wt.worktree.path
$rootPane = $wt.root_pane.pane_id
if (-not $wtPath -or -not $rootPane) { throw "unexpected worktree create response: $($wt | ConvertTo-Json -Depth 6)" }
Write-Host "  $wtPath  (workspace $($wt.workspace.workspace_id))"

# 2. a pane that starts pi itself on the ticket's provider+model. Same reason as
# herdr-build.ps1 not to use `herdr agent start`: the Windows claude/pi shims.
$pane = (Invoke-Herdr @('pane', 'split', $rootPane, '--direction', 'right',
        '--cwd', $wtPath,
        '--env', 'M2_AUTOSTART=pi',
        '--env', "M2_PROVIDER=$($modelRef.Provider)",
        '--env', "M2_MODEL=$($modelRef.Model)",
        '--env', "M2_AUTOSTART_AGENT=$role",
        '--no-focus')).pane
$paneId = $pane.pane_id
Write-Host "Pane $paneId opening, waiting for the agent..." -ForegroundColor Cyan

# 3. wait for detection, then name it. Accept any detected agent kind (pi
# reports its own), not just 'claude'.
$detectDeadline = (Get-Date).AddSeconds(90)
$detected = $false
while ((Get-Date) -lt $detectDeadline) {
    $p = (Invoke-Herdr @('pane', 'get', $paneId)).pane
    if ($p.agent) { $detected = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $detected) {
    throw "no agent detected in $paneId after 90s. Check herdr-autostart.ps1 is dot-sourced by the Windows PowerShell 5.1 profile - herdr spawns that shell, not pwsh."
}
Invoke-Herdr @('agent', 'rename', $paneId, $name) | Out-Null
Write-Host "Agent '$name' up on $($modelRef.Provider):$($modelRef.Model)" -ForegroundColor Green

# 4. hand it the brief
Invoke-Herdr @('agent', 'prompt', $name, $parsed.Body) | Out-Null
Write-Host "Brief submitted." -ForegroundColor Green

if ($NoWatch) {
    Write-Host ""
    Write-Host "Not waiting. Follow it with:  herdr agent read $name   /   herdr agent attach $name"
    if ($fallback) { Write-Host "Fallback on quota death (ticket 05, not yet automated): re-dispatch with model $fallback" -ForegroundColor DarkGray }
    return $plan
}

# 5. wait, surface blocked as the actionable state
$status = Wait-Agent -Name $name -TimeoutMs $TimeoutMs
if ($status -eq 'blocked') {
    Invoke-Herdr @('notification', 'show', "$name is blocked and needs you") | Out-Null
    Write-Host ""; Write-Host "BLOCKED - $name needs an answer:  herdr agent attach $name" -ForegroundColor Yellow
    return $plan
}
if ($status -eq 'timeout') {
    Write-Host ""; Write-Host "Timed out. The agent is still running:  herdr agent read $name" -ForegroundColor Yellow
    return $plan
}
Invoke-Herdr @('notification', 'show', "$name finished ($status)") | Out-Null
Write-Host ""; Write-Host "Finished: $status" -ForegroundColor Green
Write-Host "Worktree: $wtPath  (branch $branch)"
Write-Host "Verify the build yourself, then review:  review.ps1 -Ticket $Ticket -Verdict '<cmd> -> PASS'"
return $plan
