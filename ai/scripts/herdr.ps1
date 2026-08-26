# Shared herdr plumbing for the pane-orchestration scripts.
#
# Dot-source this: . "$HOME\.claude\scripts\herdr.ps1"
#
# dispatch.ps1 and review.ps1 both need to talk to herdr and both need to know
# when a pane has stopped being useful. That logic lives here once.
#
# The interesting part is death detection. A pi session that hits a provider
# error does NOT exit and does NOT change status: it prints the error and sits
# at `idle` forever. Observed live - a reviewer pane on a paid OpenRouter model
# printed `Error: 402: {...}` and stayed idle, so a status-only watcher waits out
# its entire timeout on a session that will never do anything again. Anything
# waiting on a pane therefore has to read the pane's output, not just its status.
#
# Keep PowerShell 5.1 compatible (herdr spawns 5.1): no ??, no ?., no ternary.

function Invoke-Herdr {
    param([string[]]$HerdrArgs)
    $raw = & herdr @HerdrArgs 2>&1 | Out-String
    try { $json = $raw | ConvertFrom-Json } catch { throw "herdr $($HerdrArgs -join ' ') returned non-JSON: $raw" }
    if ($json.error) { throw "herdr $($HerdrArgs[0]) $($HerdrArgs[1]): $($json.error.message)" }
    return $json.result
}

function Get-AgentStatus {
    param([Parameter(Mandatory)][string]$Name)
    return (Invoke-Herdr @('agent', 'get', $Name)).agent.agent_status
}

function Get-AgentPane {
    param([Parameter(Mandatory)][string]$Name)
    $a = $null
    try { $a = (Invoke-Herdr @('agent', 'get', $Name)).agent } catch { return $null }
    if (-not $a) { return $null }
    foreach ($f in 'pane_id', 'pane', 'paneId') { if ($a.$f) { return $a.$f } }
    return $null
}

function Get-AgentOutput {
    # recent-unwrapped, not the default: the wrapped view truncates each line at
    # the pane width, which cuts a provider error off mid-message and makes it
    # unmatchable. Failure to read is not fatal - the caller keeps polling.
    param([Parameter(Mandatory)][string]$Name, [int]$Lines = 200)
    try { return (& herdr agent read $Name --source recent-unwrapped --lines $Lines 2>&1 | Out-String) }
    catch { return '' }
}

# Provider deaths worth failing over: the model refused the request for reasons
# a different model would not share. 5xx and network blips are NOT here on
# purpose - those are transient, and swapping models on one hiccup would burn a
# fallback that a retry would not have needed.
$script:DeathCodes = @('401', '402', '403', '429')
$script:DeathPhrases = 'quota|rate.?limit|insufficient|credit|unauthorized|authentication|not authenticated|expired|invalid.?api.?key'

function Get-DeathLines {
    # Pure text -> the pi error lines that mean this pane is finished.
    #
    # Anchored on pi's own `Error:` rendering rather than a bare keyword search,
    # because a ticket brief is echoed into the same buffer: a ticket that says
    # "handle the rate limit" must not read as a rate-limit death.
    param([string]$Text)
    $hits = @()
    if (-not $Text) { return $hits }
    foreach ($line in ($Text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -notmatch '^Error:') { continue }
        $code = $null
        if ($t -match '^Error:\s*(\d{3})\b') { $code = $Matches[1] }
        $isDeath = $false
        if ($code -and ($script:DeathCodes -contains $code)) { $isDeath = $true }
        elseif ($t -match "(?i)$($script:DeathPhrases)") { $isDeath = $true }
        if ($isDeath) { $hits += [pscustomobject]@{ Code = $code; Line = $t } }
    }
    return $hits
}

function Wait-Agent {
    # Poll until the agent settles, dies on a provider error, or runs out of time.
    # Returns one of: done | idle | blocked | died | timeout.
    #
    # Two things this does that a naive poll does not:
    #   - it waits to SEE `working` before accepting a settled state, because the
    #     first status after submission is the state the agent was already in;
    #   - it reads output for a death every poll regardless of status, because a
    #     dead session never reaches `working` at all.
    #
    # -BaselineDeaths is the death count from before this attempt started. A
    # relaunched pane in the same session still has the previous failure in its
    # scrollback, and re-reading that as a fresh death would fail the fallback
    # over instantly on the strength of the error it just recovered from.
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutMs = 1800000,
        [int]$PollMs = 2000,
        [int]$BaselineDeaths = 0,
        [ref]$DeathLine
    )
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $sawWorking = $false
    $settled = @('idle', 'done', 'blocked')
    while ((Get-Date) -lt $deadline) {
        $deaths = @(Get-DeathLines (Get-AgentOutput -Name $Name))
        if ($deaths.Count -gt $BaselineDeaths) {
            if ($DeathLine) { $DeathLine.Value = $deaths[$deaths.Count - 1].Line }
            return 'died'
        }
        $status = Get-AgentStatus -Name $Name
        if ($status -eq 'working') { $sawWorking = $true }
        elseif ($status -eq 'blocked') { return 'blocked' }
        elseif ($sawWorking -and $settled -contains $status) { return $status }
        Start-Sleep -Milliseconds $PollMs
    }
    return 'timeout'
}

function Wait-PaneAgent {
    # Wait for herdr to detect an agent in a freshly split pane, then name it.
    param(
        [Parameter(Mandatory)][string]$PaneId,
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutSeconds = 90
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $p = (Invoke-Herdr @('pane', 'get', $PaneId)).pane
        if ($p.agent) {
            Invoke-Herdr @('agent', 'rename', $PaneId, $Name) | Out-Null
            return $true
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function New-AgentPane {
    # Split a pane and start pi in it on a specific provider+model, via the env
    # contract herdr-autostart.ps1 reads. `herdr agent start` is not used: it
    # Start-Process-es the extensionless npm shim and dies with "%1 is not a
    # valid Win32 application", so the pane's own shell starts the agent.
    param(
        [Parameter(Mandatory)][string]$FromPane,
        [Parameter(Mandatory)][string]$Cwd,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$AgentPrompt,
        [switch]$ReadOnly,
        [string]$Direction = 'right'
    )
    $splitArgs = @('pane', 'split', $FromPane, '--direction', $Direction,
        '--cwd', $Cwd,
        '--env', 'M2_AUTOSTART=pi',
        '--env', "M2_PROVIDER=$Provider",
        '--env', "M2_MODEL=$Model",
        '--env', "M2_AUTOSTART_AGENT=$AgentPrompt")
    if ($ReadOnly) { $splitArgs += @('--env', 'M2_READONLY=1') }
    $splitArgs += '--no-focus'
    return (Invoke-Herdr $splitArgs).pane.pane_id
}
