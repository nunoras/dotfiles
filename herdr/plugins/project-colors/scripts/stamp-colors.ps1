#Requires -Version 7
<#
Stamps a per-project glyph onto every herdr workspace and pane, as a
display-only metadata token named `color`.

The sidebar renders it wherever `$color` appears in a row:

    [ui.sidebar.spaces]
    rows = [["$color", "state_icon", "workspace"], ["branch", "git_status"]]

    [ui.sidebar.agents]
    rows = [["$color", "state_icon", "tab"], ["agent"]]

A project is identified by its repo name when the space has a worktree, and by
the last segment of a pane's cwd otherwise.

A project's glyph is resolved in two steps. icons.json wins: name a project
there and it carries that emoji, so metin2-server gets a castle rather than a
square nobody can decode. Anything not named there falls back to colors.json,
where a project seen for the first time takes the first colour nothing else is
using and keeps it - so no two projects ever share a colour while the palette
lasts, and a new project needs no editing at all.

Nothing here overwrites an entry that already exists in either file.

Run with -Show to print the assignment without touching anything.
#>
[CmdletBinding()]
param(
    [switch]$Show
)

$ErrorActionPreference = 'Stop'

# herdr spawns plugin commands with no shell, so nothing has set the console up
# for UTF-8 yet. Without this the emoji reaches herdr as mojibake.
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Ordered by how far apart they read in a sidebar, because the first colours in
# this list are the ones that actually get handed out. Written as codepoints
# rather than literal emoji so the file survives being read as anything but UTF-8.
$Palette = [ordered]@{
    blue   = 0x1F7E6
    green  = 0x1F7E9
    purple = 0x1F7EA
    orange = 0x1F7E7
    yellow = 0x1F7E8
    red    = 0x1F7E5
    brown  = 0x1F7EB
    white  = 0x2B1C
}

$assignmentsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'colors.json'
$iconsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'icons.json'
$source = 'nunoras.project-colors'

function Get-Glyph([string]$ColorName) {
    [char]::ConvertFromUtf32($Palette[$ColorName])
}

# Hand-edited, unlike colors.json, so it takes a literal emoji as well as the
# codepoint form the palette above uses. Keys starting with // are comments,
# which JSON has no other way to carry.
function Read-Icons {
    if (-not (Test-Path -LiteralPath $iconsPath)) { return @{} }

    $map = @{}
    $json = Get-Content -LiteralPath $iconsPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($property in $json.PSObject.Properties) {
        if ($property.Name.StartsWith('//')) { continue }

        $value = "$($property.Value)".Trim()
        if (-not $value) { continue }

        if ($value -match '^(?i:U\+[0-9a-f]{4,6})(\s+(?i:U\+[0-9a-f]{4,6}))*$') {
            $value = -join ($value -split '\s+' | ForEach-Object {
                [char]::ConvertFromUtf32([Convert]::ToInt32($_.Substring(2), 16))
            })
        }
        $map[$property.Name] = $value
    }
    $map
}

# report-metadata does not parse the way its --help prints it: the positional id
# has to come first, and option values are space-separated, never --opt=value.
function Invoke-Herdr {
    $raw = & herdr @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "herdr $($args -join ' ') failed: $raw" }
    if ($raw) { $raw | ConvertFrom-Json }
}

function Read-Assignments {
    if (-not (Test-Path -LiteralPath $assignmentsPath)) { return [ordered]@{} }

    $map = [ordered]@{}
    $json = Get-Content -LiteralPath $assignmentsPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($property in $json.PSObject.Properties) {
        # A colour that is no longer in the palette would stamp nothing at all.
        if ($Palette.Contains($property.Value)) { $map[$property.Name] = $property.Value }
    }
    $map
}

function Write-Assignments([System.Collections.Specialized.OrderedDictionary]$Map) {
    # Written aside and moved, because four events can fire at once and a
    # half-written file would lose every assignment made so far.
    $temp = "$assignmentsPath.$PID.tmp"
    $Map | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding utf8
    Move-Item -LiteralPath $temp -Destination $assignmentsPath -Force
}

$workspaces = (Invoke-Herdr workspace list).result.workspaces
$panes = (Invoke-Herdr pane list).result.panes

# A space with a worktree names itself. One without - a plain shell space - is
# named by what its panes are sitting in, which is the same thing in practice.
function Get-ProjectName($Workspace) {
    if ($Workspace.worktree.repo_name) { return $Workspace.worktree.repo_name }

    $cwd = ($panes | Where-Object { $_.workspace_id -eq $Workspace.workspace_id -and $_.cwd } |
        Select-Object -First 1).cwd
    if ($cwd) { return Split-Path -Path $cwd.TrimEnd('\', '/') -Leaf }

    $Workspace.label
}

$assigned = Read-Assignments
$icons = Read-Icons
$dirty = $false

# Defined here rather than beside Get-Glyph because it reads $assigned, which
# the loop below is still filling in.
function Resolve-Glyph([string]$Project) {
    if ($icons.ContainsKey($Project)) { return $icons[$Project] }
    Get-Glyph $assigned[$Project]
}

foreach ($project in ($workspaces | ForEach-Object { Get-ProjectName $_ } | Select-Object -Unique)) {
    if ($assigned.Contains($project)) { continue }

    $taken = @($assigned.Values)
    $free = @($Palette.Keys | Where-Object { $_ -notin $taken })

    # Past the end of the palette colours have to repeat. Reusing the least
    # recently handed out one keeps the repeats as far apart as possible.
    $assigned[$project] = if ($free) { $free[0] } else { $taken[0] }
    $dirty = $true
}

if ($dirty -and -not $Show) { Write-Assignments $assigned }

if ($Show) {
    foreach ($workspace in $workspaces) {
        $project = Get-ProjectName $workspace
        $from = if ($icons.ContainsKey($project)) { 'icons.json' } else { $assigned[$project] }
        '{0}  {1,-16} {2,-10} {3}' -f (Resolve-Glyph $project), $project, $from, $workspace.label
    }
    exit 0
}

foreach ($workspace in $workspaces) {
    $glyph = Resolve-Glyph (Get-ProjectName $workspace)

    Invoke-Herdr workspace report-metadata $workspace.workspace_id --source $source --token "color=$glyph" | Out-Null

    foreach ($pane in $panes | Where-Object { $_.workspace_id -eq $workspace.workspace_id }) {
        Invoke-Herdr pane report-metadata $pane.pane_id --source $source --token "color=$glyph" | Out-Null
    }
}
