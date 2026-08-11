# Claude Code status line.
#
# Line 1:  <model>  <context bar with a 20% marker> <pct>  <effort>   <branch>  (+ins,-del)
# Line 2:  5-hour: x% (r: ym) | weekly: x% (r: xd zh ym)
#
# The 20% marker on the context bar is the "time to start a new chat" tick.

$ErrorActionPreference = 'SilentlyContinue'

$raw = [Console]::In.ReadToEnd()
$brace = $raw.IndexOf('{')
if ($brace -gt 0) { $raw = $raw.Substring($brace) }
$d = $raw | ConvertFrom-Json

$e = [char]27
function Paint([string]$text, [string]$code) { "$e[${code}m$text$e[0m" }

# --- context bar ------------------------------------------------------------
# Marker sits at MARKER_PCT of the bar. Below it the fill is green, above it
# amber, and once the fill passes the marker the marker itself turns red.
$BAR_WIDTH = 22
$MARKER_PCT = 20

$ctxPct = $null
if ($null -ne $d.context_window.used_percentage) { $ctxPct = [double]$d.context_window.used_percentage }

$bar = ''
$ctxLabel = ''
if ($null -ne $ctxPct) {
    $clamped = [Math]::Max(0, [Math]::Min(100, $ctxPct))
    $filled = [int][Math]::Round($clamped / 100 * $BAR_WIDTH)
    $markerIdx = [int][Math]::Round($MARKER_PCT / 100 * $BAR_WIDTH)

    $past = $clamped -ge $MARKER_PCT
    $fillColor = if ($past) { '38;5;215' } else { '38;5;114' }
    $markerColor = if ($past) { '38;5;203' } else { '38;5;244' }

    for ($i = 0; $i -lt $BAR_WIDTH; $i++) {
        if ($i -eq $markerIdx) { $bar += Paint '|' $markerColor }
        elseif ($i -lt $filled) { $bar += Paint ([char]0x2588) $fillColor }
        else { $bar += Paint ([char]0x2591) '38;5;238' }
    }

    # No window size here - the model display name already carries it ("Opus 5 (1M context)").
    $ctxLabel = Paint ("{0}%" -f [int][Math]::Round($clamped)) $fillColor
}

# --- model name, gradient ---------------------------------------------------
$modelName = $d.model.display_name
$model = ''
if ($modelName) {
    $ramp = @(60, 67, 73, 74, 80)
    for ($i = 0; $i -lt $modelName.Length; $i++) {
        $slot = [int][Math]::Floor($i / [Math]::Max(1, $modelName.Length) * $ramp.Count)
        if ($slot -ge $ramp.Count) { $slot = $ramp.Count - 1 }
        $model += "$e[1m$e[38;5;$($ramp[$slot])m" + $modelName[$i]
    }
    $model += "$e[0m"
}

# --- git branch + changes ---------------------------------------------------
$dir = $d.workspace.current_dir
if (-not $dir) { $dir = $d.cwd }
$branch = ''
$git = ''
if ($dir -and (Test-Path $dir)) {
    $head = git -C $dir rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $head) {
        # detached HEAD reports the literal "HEAD" - show the short sha instead
        if ($head -eq 'HEAD') { $head = git -C $dir rev-parse --short HEAD 2>$null }
        if ($head) { $branch = Paint $head '38;5;109' }
    }

    $numstat = git -C $dir diff --numstat HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $numstat) {
        $ins = 0; $del = 0
        foreach ($line in $numstat) {
            $parts = $line -split "`t"
            if ($parts.Count -ge 2) {
                # binary files report "-" on both counts
                if ($parts[0] -match '^\d+$') { $ins += [int]$parts[0] }
                if ($parts[1] -match '^\d+$') { $del += [int]$parts[1] }
            }
        }
        if ($ins -gt 0 -or $del -gt 0) { $git = Paint "(+$ins,-$del)" '38;5;178' }
    }
}

# --- usage windows ----------------------------------------------------------
function Remaining($resetsAt) {
    if ($null -eq $resetsAt) { return $null }
    $span = [DateTimeOffset]::FromUnixTimeSeconds([long]$resetsAt).LocalDateTime - (Get-Date)
    if ($span.TotalSeconds -le 0) { return '0m' }
    $parts = @()
    if ($span.Days -gt 0) { $parts += "$($span.Days)d" }
    if ($span.Hours -gt 0) { $parts += "$($span.Hours)h" }
    $parts += "$($span.Minutes)m"
    return ($parts -join ' ')
}

function UsagePart([string]$label, $window, [string]$color) {
    if ($null -eq $window.used_percentage) { return $null }
    $text = "{0}: {1}%" -f $label, [int][Math]::Round([double]$window.used_percentage)
    $left = Remaining $window.resets_at
    if ($left) { $text += " (r: $left)" }
    return Paint $text $color
}

$five = UsagePart '5-hour' $d.rate_limits.five_hour '38;5;111'
$week = UsagePart 'weekly' $d.rate_limits.seven_day '38;5;111'

# --- assemble ---------------------------------------------------------------
function Visible([string]$s) { ($s -replace "$e\[[0-9;]*m", '').Length }

# A non-Anthropic session gets badged. The thing that must never happen is
# believing you are on GLM while spending Anthropic quota. Set by scripts/glm.ps1.
$vendor = ''
if ($env:M2_VENDOR) { $vendor = Paint " $($env:M2_VENDOR.ToUpper()) " '1;38;5;231;48;5;97' }

$left = @($vendor, $model, $bar, $ctxLabel) | Where-Object { $_ }
if ($d.effort.level) { $left += Paint $d.effort.level '38;5;96' }
$line1 = ($left -join '  ')

$right = (@($branch, $git) | Where-Object { $_ }) -join '  '
if ($right) {
    $width = 0
    try { $width = $Host.UI.RawUI.BufferSize.Width } catch { }
    $pad = $width - 6 - (Visible $line1) - (Visible $right)
    if ($pad -lt 1) { $pad = 1 }
    $line1 += (' ' * $pad) + $right
}

$parts2 = @($five, $week) | Where-Object { $_ }
$line2 = ($parts2 -join (Paint ' | ' '38;5;240'))

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$out = @($line1, $line2) | Where-Object { $_ }
Write-Output ($out -join "`n")
