# Checks the skills that exist in both harness sets are still identical.
#   pwsh -File ai/scripts/skills-mirror.tests.ps1
#
# Claude Code reads ai/skills, pi reads pi/skills, and neither reads the other.
# A few skills are harness-agnostic prose and live in both, which means an edit
# to one copy silently leaves the other behind - and the symptom is not an
# error, it is one harness quietly behaving like an older version of itself.
#
# Skills present in only one set are fine and expected: `orchestrator` exists in
# both with deliberately different content, which is why this compares an
# explicit list rather than every shared directory name.
#
# Keep PowerShell 5.1 compatible: no ??, no ?., no ternary.

$ErrorActionPreference = 'Stop'

# Resolve the repo root through the symlink: ~/.claude/scripts may be a link to
# ai/scripts, in which case $PSScriptRoot's parent is ~/.claude, not the repo.
$scriptDir = $PSScriptRoot
$item = Get-Item -LiteralPath $PSScriptRoot -Force -ErrorAction SilentlyContinue
if ($item -and $item.Target) {
    $target = @($item.Target)[0]
    if ($target) { $scriptDir = $target }
}
$repoRoot = Split-Path (Split-Path $scriptDir -Parent) -Parent

$mirrored = @('grilling', 'grill-with-docs', 'domain-modeling')

$failures = 0
function Fail { param([string]$Message)
    Write-Host "  FAIL  $Message" -ForegroundColor Red; $script:failures++ }

# Compared with line endings stripped: the two trees are checked out by the same
# git but a copy made by hand can pick up the other convention, and that is not
# a difference anybody means.
function Get-NormalizedHash {
    param([string]$Path)
    $text = [IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)) }
    finally { $sha.Dispose() }
}

Write-Host "mirrored skills are in sync"
foreach ($skill in $mirrored) {
    $a = Join-Path $repoRoot "ai\skills\$skill"
    $b = Join-Path $repoRoot "pi\skills\$skill"

    if (-not (Test-Path $a)) { Fail "$skill is missing from ai/skills (Claude Code loses it)"; continue }
    if (-not (Test-Path $b)) { Fail "$skill is missing from pi/skills (pi loses it)"; continue }

    $aFiles = @(Get-ChildItem $a -Recurse -File | ForEach-Object { $_.FullName.Substring($a.Length).TrimStart('\') } | Sort-Object)
    $bFiles = @(Get-ChildItem $b -Recurse -File | ForEach-Object { $_.FullName.Substring($b.Length).TrimStart('\') } | Sort-Object)

    $onlyA = @($aFiles | Where-Object { $bFiles -notcontains $_ })
    $onlyB = @($bFiles | Where-Object { $aFiles -notcontains $_ })
    if ($onlyA.Count -gt 0) { Fail "$skill : only in ai/skills -> $($onlyA -join ', ')" }
    if ($onlyB.Count -gt 0) { Fail "$skill : only in pi/skills -> $($onlyB -join ', ')" }

    $differing = @()
    foreach ($rel in $aFiles) {
        if ($bFiles -notcontains $rel) { continue }
        if ((Get-NormalizedHash (Join-Path $a $rel)) -ne (Get-NormalizedHash (Join-Path $b $rel))) { $differing += $rel }
    }
    if ($differing.Count -gt 0) { Fail "$skill : content differs in $($differing -join ', ')" }
    elseif ($onlyA.Count -eq 0 -and $onlyB.Count -eq 0) { Write-Host "  PASS  $skill" }
}

Write-Host ""
if ($failures -gt 0) {
    Write-Host "$failures failure(s). Copy the newer version over the older one - both harnesses are supposed to read the same thing." -ForegroundColor Red
    exit 1
}
Write-Host "all passed" -ForegroundColor Green
