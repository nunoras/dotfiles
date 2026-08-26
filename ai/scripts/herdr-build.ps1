# Run a GLM build as a visible, steerable herdr pane instead of a blind
# headless shell-out.
#
#   .\herdr-build.ps1 -Ticket 42 -Brief (Get-Content brief.md -Raw)
#   .\herdr-build.ps1 -Ticket 42 -Brief $b -NoWatch   # dispatch several at once
#   .\herdr-build.ps1 -Ticket 42 -Close               # tear it down afterwards
#
# The headless path (glm.ps1 -Prompt) is still the right one when a Claude
# session dispatches unattended. Use this one when you are at the keyboard,
# because it buys three things headless cannot:
#
#   1. `blocked` is recoverable. A headless run that stops for a permission
#      prompt or to ask a question is a wasted dispatch. Here you just answer.
#   2. You can watch it go wrong early instead of reading about it at the end.
#   3. Several builds run side by side, which is the only way a cheap execution
#      subscription actually pays for itself.

[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Build')][string]$Brief,

    # -Close <ticket> tears the build down instead of starting one.
    [Parameter(Mandatory, ParameterSetName = 'Build')]
    [Parameter(Mandatory, ParameterSetName = 'Close')]
    [string]$Ticket,
    [Parameter(Mandatory, ParameterSetName = 'Close')][switch]$Close,

    [string]$Repo = (Get-Location).Path,
    [string]$Base = "main",
    [string]$Model = "glm-5.2",
    [string]$Agent = "builder",

    # Watching is the entire reason this path exists, so it is the default.
    # -NoWatch dispatches and returns, for when you want several going at once.
    [Parameter(ParameterSetName = 'Build')][switch]$NoWatch,

    [int]$TimeoutMs = 1800000
)

$ErrorActionPreference = 'Stop'

function Invoke-Herdr {
    param([string[]]$HerdrArgs)
    $raw = & herdr @HerdrArgs 2>&1 | Out-String
    try { $json = $raw | ConvertFrom-Json } catch { throw "herdr $($HerdrArgs -join ' ') returned non-JSON: $raw" }
    if ($json.error) { throw "herdr $($HerdrArgs[0]) $($HerdrArgs[1]): $($json.error.message)" }
    return $json.result
}

# `agent prompt --wait` matches the first state observed *after* submission, so
# it hangs when the agent has not started working yet, or when it finished
# before the watch began. Poll instead: only treat a settled state as the end
# once the agent has actually been seen working.
function Wait-Agent {
    param(
        [string]$Name,
        [int]$TimeoutMs = 1800000,
        [int]$PollMs = 2000
    )
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

$slug = ($Ticket -replace '[^\w\-]', '-').Trim('-').ToLower()
$name = "glm-$slug"
$branch = "ticket/$slug"

# --- teardown ---------------------------------------------------------------
# Split out because getting it wrong destroys work. Two things bite:
#
#   1. `worktree remove` fails with "Permission denied" while the pane is still
#      alive, because the pane's shell holds the directory as its cwd. The
#      workspace has to be closed first - and closing it deregisters the
#      worktree anyway, so the remove afterwards reports workspace_not_found.
#   2. An uncommitted change in there is gone forever the moment it is removed.
#      builder.md tells the builder to commit, but a build that was interrupted,
#      or that stopped to ask a question, will not have.
if ($Close) {
    $wtPath = Join-Path $HOME ".herdr\worktrees\$(Split-Path $Repo -Leaf)\ticket-$slug"

    if (Test-Path $wtPath) {
        $dirty = @(& git -C $wtPath status --porcelain 2>$null)
        if ($dirty.Count -gt 0) {
            Write-Host ""
            Write-Host "REFUSING to close: $wtPath has uncommitted changes." -ForegroundColor Red
            $dirty | ForEach-Object { Write-Host "  $_" }
            Write-Host ""
            Write-Host "Removing it would destroy them. Commit them on $branch first:" -ForegroundColor Yellow
            Write-Host "  git -C `"$wtPath`" add -A && git -C `"$wtPath`" commit"
            exit 1
        }
    }

    $ws = (Invoke-Herdr @('workspace', 'list')).workspaces |
        Where-Object { $_.label -eq "build $Ticket" } | Select-Object -First 1
    if ($ws) {
        Write-Host "Closing workspace $($ws.workspace_id)..." -ForegroundColor Cyan
        Invoke-Herdr @('workspace', 'close', $ws.workspace_id) | Out-Null
        Start-Sleep -Seconds 2
    }

    # Closing the workspace usually deregisters the worktree by itself, so a
    # failure here is expected and not worth reporting as one.
    & git -C $Repo worktree remove $wtPath --force 2>$null | Out-Null
    & git -C $Repo worktree prune 2>$null | Out-Null
    if (Test-Path $wtPath) { Remove-Item $wtPath -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "Closed. Branch $branch is kept - `worktree remove` never deletes it." -ForegroundColor Green
    Write-Host "  git log --oneline -1 $branch"
    Write-Host "  git branch -d $branch    # once it is merged"
    exit 0
}

# --- 1. an isolated, *visible* worktree ------------------------------------
# isolation:worktree on the agent would also work, but its path is a temp dir
# you have to be told about. A herdr worktree is a workspace you can switch to
# and inspect while the build is still running.
Write-Host "Creating worktree $branch from $Base..." -ForegroundColor Cyan
$wt = Invoke-Herdr @('worktree', 'create', '--cwd', $Repo, '--branch', $branch, '--base', $Base, '--label', "build $Ticket")
$wtPath = $wt.worktree.path
$rootPane = $wt.root_pane.pane_id
if (-not $wtPath -or -not $rootPane) {
    throw "unexpected worktree create response: $($wt | ConvertTo-Json -Depth 6)"
}
Write-Host "  $wtPath  (workspace $($wt.workspace.workspace_id))"

# --- 2. a pane that starts the agent itself ---------------------------------
# NOT `herdr agent start --kind claude`: that runs `Start-Process -FilePath
# claude`, which on a Windows npm install resolves to the extensionless `claude`
# (a /bin/sh script) rather than claude.cmd and dies with "%1 is not a valid
# Win32 application". Instead the pane is opened with M2_AUTOSTART set, and
# herdr-autostart.ps1 (dot-sourced by both PowerShell profiles) launches
# glm.ps1. herdr's own detection then picks the agent up.
# Split the new workspace's own root pane, not the caller's, so the build lives
# in the worktree workspace rather than scattered across whatever tab you were
# in. The root pane stays as a plain shell in the worktree, which is handy for
# running git or the tests by hand while the build works.
$pane = (Invoke-Herdr @('pane', 'split', $rootPane, '--direction', 'right',
        '--cwd', $wtPath,
        '--env', 'M2_AUTOSTART=glm',
        '--env', "M2_AUTOSTART_AGENT=$Agent",
        '--no-focus')).pane
$paneId = $pane.pane_id
Write-Host "Pane $paneId opening, waiting for the agent..." -ForegroundColor Cyan

# --- 3. wait for detection, then name it ------------------------------------
$detectDeadline = (Get-Date).AddSeconds(90)
$detected = $false
while ((Get-Date) -lt $detectDeadline) {
    $p = (Invoke-Herdr @('pane', 'get', $paneId)).pane
    if ($p.agent -eq 'claude') { $detected = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $detected) {
    throw "no agent detected in $paneId after 90s. Check that herdr-autostart.ps1 is dot-sourced by the Windows PowerShell 5.1 profile - herdr spawns that shell, not pwsh."
}
Invoke-Herdr @('agent', 'rename', $paneId, $name) | Out-Null
Write-Host "Agent '$name' up on $Model" -ForegroundColor Green

# --- 4. hand it the brief ---------------------------------------------------
# No --wait here; see Wait-Agent for why.
Invoke-Herdr @('agent', 'prompt', $name, $Brief) | Out-Null
Write-Host "Brief submitted." -ForegroundColor Green

if ($NoWatch) {
    Write-Host ""
    Write-Host "Not waiting. Follow it with:"
    Write-Host "  herdr agent read $name"
    Write-Host "  herdr agent attach $name"
    Write-Host ""
    Write-Host "Do not hand-roll a poller - `agent get` reports idle both before the"
    Write-Host "agent starts and after it finishes, so a naive loop reads a finished"
    Write-Host "build as a hung one. Rerun this script with -Watch semantics, or use"
    Write-Host "  herdr agent wait $name --until blocked idle done"
    return
}

# --- 5. wait, and surface `blocked` as the actionable state -----------------
$status = Wait-Agent -Name $name -TimeoutMs $TimeoutMs

if ($status -eq 'blocked') {
    # The case the headless path simply loses: a permission prompt, or the
    # builder stopping to ask rather than guessing. Here it is answerable.
    Invoke-Herdr @('notification', 'show', "$name is blocked and needs you") | Out-Null
    Write-Host ""
    Write-Host "BLOCKED - $name needs an answer." -ForegroundColor Yellow
    Write-Host "  herdr agent attach $name" -ForegroundColor Yellow
    return
}

if ($status -eq 'timeout') {
    Write-Host ""
    Write-Host "Timed out after $([int]($TimeoutMs/60000))m. The agent is still running." -ForegroundColor Yellow
    Write-Host "  herdr agent read $name"
    return
}

Invoke-Herdr @('notification', 'show', "$name finished ($status)") | Out-Null
Write-Host ""
Write-Host "Finished: $status" -ForegroundColor Green
Write-Host "Worktree: $wtPath  (branch $branch)"
Write-Host ""
Write-Host "Read the report, run the verify command yourself, then review it:"
Write-Host "  herdr agent read $name"
Write-Host "  # the verify command comes from the repo's CLAUDE.md table, by the paths the diff touched"
Write-Host "  pwsh -File `"$HOME\.claude\scripts\gpt-review.ps1`" -Cwd `"$wtPath`" -Base $Base -Context `"<the brief>`" -BuildVerdict `"<command> -> PASS`""
Write-Host ""
Write-Host "-BuildVerdict is required and the script will refuse without it. GPT cannot"
Write-Host "run anything on this machine, so with no verdict it reports `"no compiler"
Write-Host "verdict`" and reviews around the hole. Run the command yourself first."
Write-Host ""
Write-Host "-Base only sees committed work. If the review says there is nothing to"
Write-Host "review, the builder did not commit - check `git -C `"$wtPath`" status`."
Write-Host ""
Write-Host "When you are done with it:"
Write-Host "  pwsh -File `"$PSCommandPath`" -Close -Ticket $Ticket -Repo `"$Repo`""
