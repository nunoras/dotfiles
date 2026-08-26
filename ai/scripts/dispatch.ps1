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
#
# While watching, a session that dies on a provider error (quota, rate limit,
# auth) is failed over onto the ticket's `fallbackModels`, one attempt per
# level. pi has no mid-session fallback of its own for these providers, so this
# is the only thing standing between an exhausted subscription and a pane that
# sits idle forever. The final report always names the model that actually
# finished.

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
. (Join-Path $PSScriptRoot 'herdr.ps1')

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
$fallback = $fm['fallbackModels']   # comma-separated; empty means no failover

# Roster roles are per-model slots ('builder-a', 'builder-b'); agent definitions
# are per-job ('builder.md'). Resolve the exact name first, then the job prefix,
# and refuse to launch a builder with no system prompt at all - autostart only
# warns about a missing file, and the warning scrolls past inside the pane.
function Resolve-AgentPrompt {
    param([Parameter(Mandatory)][string]$Role)
    $dir = Join-Path $HOME '.claude\agents'
    $candidates = @($Role)
    $dash = $Role.LastIndexOf('-')
    if ($dash -ge 1) { $candidates += $Role.Substring(0, $dash) }
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $dir "$c.md")) { return $c }
    }
    throw "no agent definition for role '$Role': tried $((($candidates | ForEach-Object { "$_.md" }) -join ', ')) in $dir"
}
# Only the pi harness consumes it; the claude path is a stub, and the planner
# has no agent definition because it is a person's session.
$agentPrompt = $null
if ($harness -eq 'pi') { $agentPrompt = Resolve-AgentPrompt -Role $role }

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
    AgentPrompt = $agentPrompt
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
    Write-Host "  pi -a --provider $($modelRef.Provider) --model $($modelRef.Model) --append-system-prompt <~/.claude/agents/$agentPrompt.md>" -ForegroundColor Green
    Write-Host "  then submit the ticket brief and watch." -ForegroundColor Green
    return $plan
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

# 2. start the agent, and be able to do it again on another model.
function Start-Attempt {
    param([Parameter(Mandatory)]$Ref)
    $paneId = New-AgentPane -FromPane $rootPane -Cwd $wtPath -Provider $Ref.Provider -Model $Ref.Model -AgentPrompt $agentPrompt
    Write-Host "Pane $paneId opening on $($Ref.Provider):$($Ref.Model), waiting for the agent..." -ForegroundColor Cyan
    if (-not (Wait-PaneAgent -PaneId $paneId -Name $name)) {
        throw "no agent detected in $paneId after 90s. Check herdr-autostart.ps1 is dot-sourced by the Windows PowerShell 5.1 profile - herdr spawns that shell, not pwsh."
    }
    Write-Host "Agent '$name' up on $($Ref.Provider):$($Ref.Model)" -ForegroundColor Green
    Invoke-Herdr @('agent', 'prompt', $name, $parsed.Body) | Out-Null
    Write-Host "Brief submitted." -ForegroundColor Green
    return $paneId
}

$attempts = @($modelRef)
foreach ($f in ($fallback -split ',')) {
    $f = $f.Trim()
    if ($f) { $attempts += (Split-ModelRef $f) }
}

$paneId = Start-Attempt -Ref $modelRef

if ($NoWatch) {
    Write-Host ""
    Write-Host "Not waiting. Follow it with:  herdr agent read $name   /   herdr agent attach $name"
    if ($fallback) { Write-Host "Not watching means no fallback: a quota death will just sit there. Re-dispatch on $fallback by hand." -ForegroundColor DarkGray }
    return $plan
}

# 3. watch, failing over on a provider death. One attempt per fallback level and
# no further: if the fallback dies the same way, that is a wall, not a blip.
$i = 0
$deaths = 0
$finishedOn = $null
while ($true) {
    $ref = $attempts[$i]
    $line = ''
    $status = Wait-Agent -Name $name -TimeoutMs $TimeoutMs -BaselineDeaths $deaths -DeathLine ([ref]$line)

    if ($status -ne 'died') { $finishedOn = $ref; break }

    $deaths++
    Write-Host ""
    Write-Host "$($ref.Provider):$($ref.Model) died: $line" -ForegroundColor Yellow
    if ($i -ge ($attempts.Count - 1)) {
        Invoke-Herdr @('notification', 'show', "$name died on $($ref.Provider):$($ref.Model) and has no fallback left") | Out-Null
        Write-Host "No fallback left. The ticket is NOT done." -ForegroundColor Red
        Write-Host "  herdr agent read $name"
        $plan | Add-Member -NotePropertyName Outcome -NotePropertyValue 'died' -Force
        $plan | Add-Member -NotePropertyName FinishedOn -NotePropertyValue $null -Force
        return $plan
    }
    $i++
    $next = $attempts[$i]
    Write-Host "Failing over to $($next.Provider):$($next.Model)..." -ForegroundColor Yellow
    # Close the dead pane rather than driving its TUI: the pi session is still
    # alive and idle after the error, and re-prompting it would just hit the
    # same provider again.
    Invoke-Herdr @('pane', 'close', $paneId) | Out-Null
    Start-Sleep -Seconds 2
    $paneId = Start-Attempt -Ref $next
}

$ranOn = "$($finishedOn.Provider):$($finishedOn.Model)"
$plan | Add-Member -NotePropertyName Outcome -NotePropertyValue $status -Force
$plan | Add-Member -NotePropertyName FinishedOn -NotePropertyValue $ranOn -Force

if ($status -eq 'blocked') {
    Invoke-Herdr @('notification', 'show', "$name is blocked and needs you") | Out-Null
    Write-Host ""; Write-Host "BLOCKED - $name needs an answer:  herdr agent attach $name" -ForegroundColor Yellow
    return $plan
}
if ($status -eq 'timeout') {
    Write-Host ""; Write-Host "Timed out. The agent is still running:  herdr agent read $name" -ForegroundColor Yellow
    return $plan
}
Invoke-Herdr @('notification', 'show', "$name finished ($status) on $ranOn") | Out-Null
Write-Host ""; Write-Host "Finished: $status" -ForegroundColor Green
# Named every time, not just after a failover: "it passed" means nothing without
# knowing which model it passed on.
if ($ranOn -eq "$($modelRef.Provider):$($modelRef.Model)") { Write-Host "Ran on $ranOn (the ticket's model)." }
else { Write-Host "Ran on $ranOn - a FALLBACK, not the ticket's $($modelRef.Provider):$($modelRef.Model)." -ForegroundColor Yellow }
Write-Host "Worktree: $wtPath  (branch $branch)"
Write-Host "Verify the build yourself, then review:  review.ps1 -Ticket $Ticket -Verdict '<cmd> -> PASS'"
return $plan
