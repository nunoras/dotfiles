#Requires -Version 7
<#
Resolves a file path taken from a herdr pane and either opens it in the editor at
the right line, or reveals it in Explorer.

Input, in order of preference:
  HERDR_PLUGIN_CLICKED_URL              set when a link handler fired
  HERDR_PLUGIN_CONTEXT_JSON.selected_text  set when a selection action fired

Relative paths resolve against the focused pane's cwd, which the context JSON
carries as focused_pane_cwd.

Editor: $env:HERDR_OPEN_PATH_EDITOR ("zed" or "cursor"), default zed.
#>
[CmdletBinding()]
param(
    [ValidateSet('open', 'reveal')]
    [string]$Mode = 'open'
)

$ErrorActionPreference = 'Stop'

$logDir = if ($env:HERDR_PLUGIN_STATE_DIR) { $env:HERDR_PLUGIN_STATE_DIR } else { $PSScriptRoot }
$log = Join-Path $logDir 'open-path.log'

function Write-Log([string]$Message) {
    "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message | Add-Content -LiteralPath $log
}

$context = $null
if ($env:HERDR_PLUGIN_CONTEXT_JSON) {
    try { $context = $env:HERDR_PLUGIN_CONTEXT_JSON | ConvertFrom-Json } catch { Write-Log "context JSON did not parse: $_" }
}

$raw = $env:HERDR_PLUGIN_CLICKED_URL
if (-not $raw) { $raw = $context.selected_text }
if (-not $raw) {
    Write-Log "nothing to open: no clicked_url and no selected_text"
    exit 1
}

$text = $raw.Trim()

# A file:// URL from a link handler, rather than raw pane text.
if ($text -match '^file:///') {
    $text = [uri]::UnescapeDataString($text.Substring(8)) -replace '/', '\'
}

# Trim the punctuation that sentence context tends to glue onto a path.
$text = $text -replace '^[\("''`\[]+', '' -replace '[\)\]"''`.,;:]+$', ''

# path[:line[:col]] - the digits requirement keeps a drive letter (N:\...) intact.
$line = $null
if ($text -match '^(?<path>.+?):(?<line>\d+)(?::(?<col>\d+))?$') {
    $line = [int]$Matches['line']
    $text = $Matches['path']
}

$path = $text
if (-not [System.IO.Path]::IsPathRooted($path)) {
    $base = $context.focused_pane_cwd
    if (-not $base) {
        try {
            $base = (herdr pane current | ConvertFrom-Json).result.pane.cwd
        } catch {
            Write-Log "could not resolve a base cwd: $_"
        }
    }
    if ($base) { $path = Join-Path $base $path }
}

try { $path = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path } catch { }

if (-not (Test-Path -LiteralPath $path)) {
    Write-Log "no such path: $path (from '$raw')"
    exit 1
}

if ($Mode -eq 'reveal') {
    # /select, wants the item highlighted inside its parent folder. A directory
    # has no parent worth showing, so open it directly.
    if (Test-Path -LiteralPath $path -PathType Container) {
        Start-Process explorer.exe -ArgumentList "`"$path`""
    } else {
        Start-Process explorer.exe -ArgumentList "/select,`"$path`""
    }
    Write-Log "revealed $path"
    exit 0
}

$editor = if ($env:HERDR_OPEN_PATH_EDITOR) { $env:HERDR_OPEN_PATH_EDITOR } else { 'zed' }
$target = if ($line) { "${path}:${line}" } else { $path }

switch ($editor) {
    'zed'    { Start-Process 'zed'    -ArgumentList $target -ErrorAction Stop }
    'cursor' { Start-Process 'cursor' -ArgumentList @('-g', $target) -ErrorAction Stop }
    'code'   { Start-Process 'code'   -ArgumentList @('-g', $target) -ErrorAction Stop }
    default  { Start-Process $editor  -ArgumentList $target -ErrorAction Stop }
}

Write-Log "opened $target in $editor"
