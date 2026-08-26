# Plain assertions for roster.ps1 - no Pester dependency, runs on 5.1 or pwsh.
#   pwsh -File ai/scripts/roster.tests.ps1
# Exits non-zero on first failure.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'roster.ps1')

$failures = 0
function Assert-Eq {
    param($Actual, $Expected, [string]$Name)
    if ($Actual -eq $Expected) {
        Write-Host "  PASS  $Name"
    } else {
        Write-Host "  FAIL  $Name -> expected '$Expected', got '$Actual'" -ForegroundColor Red
        $script:failures++
    }
}
function Assert-True {
    param($Actual, [string]$Name)
    if ($Actual) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name -> expected true" -ForegroundColor Red; $script:failures++ }
}
function Assert-Throws {
    param([scriptblock]$Block, [string]$Name)
    $threw = $false
    try { & $Block } catch { $threw = $true }
    if ($threw) { Write-Host "  PASS  $Name" } else { Write-Host "  FAIL  $Name -> expected throw" -ForegroundColor Red; $script:failures++ }
}

Write-Host "Get-Harness"
Assert-Eq (Get-Harness -Provider 'anthropic')   'claude' 'anthropic -> claude'
Assert-Eq (Get-Harness -Provider 'zai')         'pi'     'zai -> pi'
Assert-Eq (Get-Harness -Provider 'openrouter')  'pi'     'openrouter -> pi'
Assert-Eq (Get-Harness -Provider 'openai-codex') 'pi'    'openai-codex -> pi'

Write-Host "Split-ModelRef"
$a = Split-ModelRef 'zai:glm-5.3'
Assert-Eq $a.Provider 'zai'     'simple provider'
Assert-Eq $a.Model    'glm-5.3' 'simple model'
$b = Split-ModelRef 'openrouter:z-ai/glm-5.3'
Assert-Eq $b.Provider 'openrouter'   'slashed model provider'
Assert-Eq $b.Model    'z-ai/glm-5.3' 'slashed model id (first colon only)'
# OpenRouter free ids carry their own colon, so the split must not be greedy.
$c = Split-ModelRef 'openrouter:z-ai/glm-5.2:free'
Assert-Eq $c.Provider 'openrouter'          'free-tier ref provider'
Assert-Eq $c.Model    'z-ai/glm-5.2:free'   'free-tier ref keeps its own colon'
Assert-Throws { Split-ModelRef 'glm-5.3' }  'no colon throws'
Assert-Throws { Split-ModelRef 'zai:' }     'empty id throws'

Write-Host "Get-RosterEntry"
$p = Get-RosterEntry -Role 'planner'
Assert-Eq $p.Primary  'anthropic:claude-fable-5' 'planner primary'
Assert-Eq $p.Fallback 'anthropic:claude-opus-5'  'planner fallback'
$ba = Get-RosterEntry -Role 'builder-a'
Assert-Eq $ba.Primary 'zai:glm-5.3'              'builder-a primary'
Assert-Throws { Get-RosterEntry -Role 'nope' }   'unknown role throws'

Write-Host "Get-RoleHarness"
Assert-Eq (Get-RoleHarness -Role 'planner')   'claude' 'planner -> claude'
Assert-Eq (Get-RoleHarness -Role 'builder-a') 'pi'     'builder-a -> pi'
Assert-Eq (Get-RoleHarness -Role 'reviewer')  'pi'     'reviewer -> pi'

Write-Host "Get-RosterFrontmatter"
$fmA = Get-RosterFrontmatter -Role 'builder-a'
Assert-True ($fmA -match '(?m)^role: builder-a$')                            'stamps the role slot verbatim'
Assert-True ($fmA -match '(?m)^model: zai:glm-5\.3$')                        'stamps the roster primary as provider:id'
Assert-True ($fmA -match '(?m)^fallbackModels: openrouter:z-ai/glm-5\.2:free$') 'stamps the roster fallback'
Assert-True ($fmA -match '(?m)^base: main$')                                 'base defaults to main'
$fmB = Get-RosterFrontmatter -Role 'builder-b' -Base 'develop'
Assert-True ($fmB -match '(?m)^base: develop$')                              'base is overridable'
Assert-True ($fmB -match '(?m)^model: openrouter:stealth/ox-alpha$')         'builder-b primary'
# The reviewer has no fallback on purpose, so the key must be absent rather
# than present and empty - dispatch treats an empty value as "no fallback"
# either way, but a bare key reads like an oversight.
$fmR = Get-RosterFrontmatter -Role 'reviewer'
Assert-True ($fmR -notmatch 'fallbackModels')                                'no fallback key when the roster has none'
Assert-Throws { Get-RosterFrontmatter -Role 'nope' }                         'unknown role throws'

Write-Host ""
if ($failures -gt 0) { Write-Host "$failures failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "all passed" -ForegroundColor Green
