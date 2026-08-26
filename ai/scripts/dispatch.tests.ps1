# Plain assertions for dispatch.ps1 - frontmatter parse, harness derivation,
# and the claude stub. No panes are spawned; everything runs via -DryRun or a
# child process. Runs on pwsh 7 and Windows PowerShell 5.1.
#   pwsh -File ai/scripts/dispatch.tests.ps1

$ErrorActionPreference = 'Stop'
$dispatch = Join-Path $PSScriptRoot 'dispatch.ps1'
$tmp = Join-Path $env:TEMP ("dispatch_tests_" + $PID)
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$failures = 0
function Assert-Eq { param($Actual, $Expected, [string]$Name)
    if ($Actual -eq $Expected) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name -> expected '$Expected', got '$Actual'" -ForegroundColor Red; $script:failures++ } }
function Assert-Throws { param([scriptblock]$Block, [string]$Name)
    $threw = $false; try { & $Block } catch { $threw = $true }
    if ($threw) { Write-Host "  PASS  $Name" } else { Write-Host "  FAIL  $Name -> expected throw" -ForegroundColor Red; $script:failures++ } }

function New-Ticket { param([string]$File, [string]$Content)
    $p = Join-Path $tmp $File; Set-Content -Path $p -Value $Content -Encoding UTF8; return $p }

# DryRun returns the plan object on the success stream; Write-Host output does not pollute it.
function Get-Plan { param([string]$TicketPath)
    return (& $dispatch -Ticket $TicketPath -Repo $tmp -DryRun | Where-Object { $_ -is [pscustomobject] } | Select-Object -Last 1) }

Write-Host "pi builder ticket"
$t1 = New-Ticket 'builder-a.md' @"
---
role: builder
model: zai:glm-5.3
fallbackModels: openrouter:z-ai/glm-5.3
base: develop
---

## Brief

Implement the widget.
"@
$p1 = Get-Plan $t1
Assert-Eq $p1.Provider 'zai'        'provider parsed'
Assert-Eq $p1.Model    'glm-5.3'    'model parsed'
Assert-Eq $p1.Harness  'pi'         'harness derived pi'
Assert-Eq $p1.Role     'builder'    'role parsed'
Assert-Eq $p1.Base     'develop'    'base parsed'
Assert-Eq $p1.Fallback 'openrouter:z-ai/glm-5.3' 'fallback parsed'
Assert-Eq ($p1.BriefChars -gt 0) $true 'brief body parsed non-empty'

Write-Host "slashed model id + default base"
$t2 = New-Ticket 'builder-b.md' @"
---
role: builder
model: openrouter:stealth/ox-alpha
---

## Brief

Do it.
"@
$p2 = Get-Plan $t2
Assert-Eq $p2.Provider 'openrouter'        'slashed provider'
Assert-Eq $p2.Model    'stealth/ox-alpha'  'slashed model id kept whole'
Assert-Eq $p2.Base     'main'              'base defaults to main'

Write-Host "reviewer harness"
$t3 = New-Ticket 'reviewer.md' @"
---
role: reviewer
model: openrouter:openai/gpt-5.5
---
brief
"@
Assert-Eq (Get-Plan $t3).Harness 'pi' 'reviewer -> pi'

Write-Host "role -> agent definition"
$t5 = New-Ticket 'slotted.md' @"
---
role: builder-a
model: zai:glm-5.3
---
brief
"@
Assert-Eq (Get-Plan $t5).AgentPrompt 'builder' 'roster slot builder-a falls back to builder.md'
Assert-Eq (Get-Plan $t1).AgentPrompt 'builder' 'exact role name is preferred'
$t6 = New-Ticket 'norole.md' @"
---
role: nonesuch
model: zai:glm-5.3
---
brief
"@
Assert-Throws { & $dispatch -Ticket $t6 -Repo $tmp -DryRun } 'unknown role has no agent definition -> throws'

Write-Host "validation"
$bad1 = New-Ticket 'nofm.md' "no frontmatter here"
Assert-Throws { & $dispatch -Ticket $bad1 -Repo $tmp -DryRun } 'missing frontmatter throws'
$bad2 = New-Ticket 'nomodel.md' @"
---
role: builder
---
brief
"@
Assert-Throws { & $dispatch -Ticket $bad2 -Repo $tmp -DryRun } 'missing model throws'

Write-Host "claude harness is stubbed (exit 2), not launched"
$t4 = New-Ticket 'planner.md' @"
---
role: planner
model: anthropic:claude-fable-5
---
brief
"@
# Run in a child process to observe the exit code without killing this one.
$psExe = (Get-Process -Id $PID).Path
& $psExe -NoProfile -File $dispatch -Ticket $t4 -Repo $tmp | Out-Null
Assert-Eq $LASTEXITCODE 2 'claude harness exits 2'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
if ($failures -gt 0) { Write-Host "$failures failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "all passed" -ForegroundColor Green
