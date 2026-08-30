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
Assert-Eq (Get-Harness -Provider 'openai-codex') 'pi'    'openai-codex is not codex, -> pi'
Assert-Eq (Get-Harness -Provider 'codex')       'codex'  'codex -> codex'
Assert-Eq (Get-Harness -Provider 'agy')         'agy'    'agy -> agy'

Write-Host "Split-ModelRef"
$a = Split-ModelRef 'zai:glm-5.3'
Assert-Eq $a.Provider 'zai'     'simple provider'
Assert-Eq $a.Model    'glm-5.3' 'simple model'
$b = Split-ModelRef 'openrouter:z-ai/glm-5.3'
Assert-Eq $b.Provider 'openrouter'   'slashed model provider'
Assert-Eq $b.Model    'z-ai/glm-5.3' 'slashed model id (first colon only)'
$c = Split-ModelRef 'openrouter:z-ai/glm-5.2:free'
Assert-Eq $c.Provider 'openrouter'          'free-tier ref provider'
Assert-Eq $c.Model    'z-ai/glm-5.2:free'   'free-tier ref keeps its own colon'
Assert-Throws { Split-ModelRef 'glm-5.3' }  'no colon throws'
Assert-Throws { Split-ModelRef 'zai:' }     'empty id throws'

Write-Host "Get-RosterEntry"
$p = Get-RosterEntry -Role 'planner'
Assert-Eq $p.Model    'anthropic:claude-fable-5' 'planner model'
Assert-Eq $p.Fallback 'anthropic:claude-opus-5'  'planner fallback'
$b = Get-RosterEntry -Role 'builder'
Assert-Eq $b.Model 'zai:glm-5.3'              'builder model'
Assert-Eq $b.Fallback 'zai:glm-5.3-flash,openrouter:z-ai/glm-5.2:free' 'builder fallback, sonnet dropped (orca-dispatch #16)'
Assert-Throws { Get-RosterEntry -Role 'nope' }   'unknown role throws'

Write-Host "Get-RoleHarness"
Assert-Eq (Get-RoleHarness -Role 'planner')   'claude' 'planner -> claude'
Assert-Eq (Get-RoleHarness -Role 'builder') 'pi'     'builder -> pi'
Assert-Eq (Get-RoleHarness -Role 'reviewer')  'pi'     'reviewer -> pi'

Write-Host "Get-RosterFrontmatter"
$fmA = Get-RosterFrontmatter -Role 'builder'
Assert-True ($fmA -match '(?m)^role: builder$')                            'stamps the role verbatim'
Assert-True ($fmA -match '(?m)^model: zai:glm-5\.3$')                        'stamps the roster model as provider:id'
Assert-True ($fmA -match '(?m)^fallbackModels: zai:glm-5\.3-flash,openrouter:z-ai/glm-5\.2:free$') 'stamps the whole fallback chain'
Assert-True ($fmA -match '(?m)^base: main$')                                 'base defaults to main'
$fmB = Get-RosterFrontmatter -Role 'builder' -Base 'develop'
Assert-True ($fmB -match '(?m)^base: develop$')                              'base is overridable'
Assert-True ($fmB -match '(?m)^model: zai:glm-5\.3$')                        'builder model'
$fmR = Get-RosterFrontmatter -Role 'reviewer'
Assert-True ($fmR -notmatch 'fallbackModels')                                'no fallback key when the roster has none'
Assert-Throws { Get-RosterFrontmatter -Role 'nope' }                         'unknown role throws'

$tmp = Join-Path ([IO.Path]::GetTempPath()) "roster-chain-$PID.json"
'{ "policy": { "spendGate": "human", "autoFallback": false, "noSelfReview": true, "maxDispatchDepth": 2 }, "roles": { "b": { "model": "zai:glm-5.3", "fallback": "openrouter:z-ai/glm-5.2:free,broken-no-colon" } } }' | Set-Content -LiteralPath $tmp -Encoding UTF8
Assert-Throws { Get-RosterFrontmatter -Role 'b' -Path $tmp }                 'a malformed level in the fallback chain throws'
'{ "policy": { "spendGate": "human", "autoFallback": false, "noSelfReview": true, "maxDispatchDepth": 2 }, "roles": { "b": { "model": "zai:glm-5.3", "fallback": "openrouter:z-ai/glm-5.2:free, zai:glm-5.3" } } }' | Set-Content -LiteralPath $tmp -Encoding UTF8
Assert-True ((Get-RosterFrontmatter -Role 'b' -Path $tmp) -match 'fallbackModels') 'a well-formed chain with spaces passes'
Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue

$flat = Join-Path ([IO.Path]::GetTempPath()) "roster-flat-$PID.json"
'{ "planner": { "primary": "anthropic:claude-fable-5", "fallback": "anthropic:claude-opus-5" } }' | Set-Content -LiteralPath $flat -Encoding UTF8
Assert-Throws { Get-RosterEntry -Role 'planner' -Path $flat }                 'a flat roster without a roles object throws'
Remove-Item -LiteralPath $flat -ErrorAction SilentlyContinue

Write-Host ""
if ($failures -gt 0) { Write-Host "$failures failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "all passed" -ForegroundColor Green
