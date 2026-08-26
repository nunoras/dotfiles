# Plain assertions for review.ps1 - verdict validation, auth-aware reviewer
# model selection, and the DryRun plan against a real temp git repo. No panes
# are spawned. Runs on pwsh 7 and Windows PowerShell 5.1.
#   pwsh -File ai/scripts/review.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'roster.ps1')
$review = Join-Path $PSScriptRoot 'review.ps1'

$failures = 0
function Assert-Eq { param($Actual, $Expected, [string]$Name)
    if ($Actual -eq $Expected) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name -> expected '$Expected', got '$Actual'" -ForegroundColor Red; $script:failures++ } }
function Assert-True { param($Cond, [string]$Name)
    if ($Cond) { Write-Host "  PASS  $Name" } else { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:failures++ } }
function Assert-Throws { param([scriptblock]$Block, [string]$Name)
    $threw = $false; try { & $Block } catch { $threw = $true }
    if ($threw) { Write-Host "  PASS  $Name" } else { Write-Host "  FAIL  $Name -> expected throw" -ForegroundColor Red; $script:failures++ } }

# --- a temp git repo with a diff on a branch off main -----------------------
$repo = Join-Path $env:TEMP ("review_tests_repo_" + $PID)
Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $repo -Force | Out-Null
Push-Location $repo
git init -q -b main
git config user.email "t@t"; git config user.name "t"
Set-Content -Path (Join-Path $repo 'f.txt') -Value "base line" -Encoding utf8
git add -A; git commit -q -m "base"
git checkout -q -b work
Add-Content -Path (Join-Path $repo 'f.txt') -Value "a change the reviewer should see" 
git add -A; git commit -q -m "the change"
Pop-Location

$ticket = Join-Path $env:TEMP ("review_ticket_" + $PID + ".md")
Set-Content -Path $ticket -Encoding utf8 -Value @"
---
role: builder
model: zai:glm-5.3
base: main
---

## Brief

UNIQUEBRIEFMARKER: implement the change.
"@

function Get-Plan { param([hashtable]$Extra)
    $splat = @{ Ticket = $ticket; Repo = $repo; DryRun = $true }
    if ($Extra) { foreach ($k in $Extra.Keys) { $splat[$k] = $Extra[$k] } }
    return (& $review @splat | Where-Object { $_ -is [pscustomobject] } | Select-Object -Last 1) }

Write-Host "verdict validation"
Assert-Throws { & $review -Ticket $ticket -Repo $repo -DryRun } 'empty verdict throws'
Assert-Throws { & $review -Ticket $ticket -Repo $repo -Verdict "ran the tests" -DryRun } 'verdict without outcome throws'

Write-Host "auth-aware reviewer model selection"
$entry = Get-RosterEntry -Role 'reviewer'
$primary = Split-ModelRef $entry.Primary
$raw = pi auth check --provider $primary.Provider --no-refresh --json 2>&1 | Out-String
$primaryReady = $false; try { $primaryReady = (($raw | ConvertFrom-Json).status -eq 'ready') } catch {}
if ($primaryReady) {
    $expect = $primary
    $p = Get-Plan @{ Verdict = 'npm test -> PASS' }
    Assert-Eq $p.Provider $expect.Provider 'reviewer provider (roster primary)'
    Assert-Eq $p.Model    $expect.Model    'reviewer model (roster primary)'
    Assert-True ($p.ModelChoice -like '*roster primary*') 'model choice explains itself (roster primary)'
} elseif ($entry.Fallback) {
    $expect = Split-ModelRef $entry.Fallback
    $p = Get-Plan @{ Verdict = 'npm test -> PASS' }
    Assert-Eq $p.Provider $expect.Provider 'reviewer provider (fallback)'
    Assert-Eq $p.Model    $expect.Model    'reviewer model (fallback)'
    Assert-True ($p.ModelChoice -like '*fallback*') 'model choice explains itself (fallback)'
} else {
    # Primary unreachable and no fallback by design: fail loudly rather than
    # quietly reviewing on a model nobody chose.
    Assert-Throws { & $review -Ticket $ticket -Repo $repo -Verdict 'npm test -> PASS' -DryRun } 'no primary and no fallback throws'
}

# Everything below is about the payload, not model choice, so pin the model and
# stay independent of what happens to be authenticated on this machine.
Write-Host "diff + task file"
$p = Get-Plan @{ Verdict = 'npm test -> PASS'; Model = 'zai:glm-5.3' }
Assert-True ($p.DiffChars -gt 0) 'diff collected non-empty'
Assert-Eq $p.Truncated $false 'small diff not truncated'
Assert-True (Test-Path $p.TaskFile) 'task file written'
$task = Get-Content $p.TaskFile -Raw
Assert-True ($task -match 'UNIQUEBRIEFMARKER') 'task file carries the brief'
Assert-True ($task -match 'npm test -> PASS') 'task file carries the verdict'
Assert-True ($task -match 'a change the reviewer should see') 'task file carries the diff'

Write-Host "model override"
$po = Get-Plan @{ Verdict = 'x -> PASS'; Model = 'zai:glm-5.3' }
Assert-Eq $po.Provider 'zai'      'override provider'
Assert-Eq $po.Model    'glm-5.3'  'override model'
Assert-Eq $po.ModelChoice 'override' 'override choice'

Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $ticket -Force -ErrorAction SilentlyContinue
Get-ChildItem $env:TEMP -Filter 'review-task-*.md' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host ""
if ($failures -gt 0) { Write-Host "$failures failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "all passed" -ForegroundColor Green
