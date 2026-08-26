# Plain assertions for herdr.ps1. Only the pure text logic is covered here -
# Get-DeathLines - because everything else in that file needs a live herdr.
# That is the piece worth pinning anyway: a false positive fails a healthy
# session over onto a fallback for no reason, and a false negative leaves a dead
# pane burning its whole timeout.
#   pwsh -File ai/scripts/herdr.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'herdr.ps1')

$failures = 0
function Assert-Eq { param($Actual, $Expected, [string]$Name)
    if ($Actual -eq $Expected) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name -> expected '$Expected', got '$Actual'" -ForegroundColor Red; $script:failures++ } }

Write-Host "real deaths"
# Captured verbatim from a reviewer pane on a paid OpenRouter model.
$openrouter402 = @"
 Ran for 5s, bash x1 - ctrl+o to show more

 Error: 402: {"message":"This request requires more credits, or fewer max_tokens. You requested up to 128000 tokens, but can only afford 1212"}

 GPT-5.5
"@
$hits = @(Get-DeathLines $openrouter402)
Assert-Eq $hits.Count 1      'the 402 is one death'
Assert-Eq $hits[0].Code '402' 'status code captured'

Assert-Eq (@(Get-DeathLines 'Error: 401: {"message":"unauthorized"}')).Count 1 '401 is a death'
Assert-Eq (@(Get-DeathLines 'Error: 429: {"message":"slow down"}')).Count 1    '429 is a death'
Assert-Eq (@(Get-DeathLines 'Error: rate limit exceeded for this key')).Count 1 'phrase without a code is a death'
Assert-Eq (@(Get-DeathLines 'Error: OAuth token expired')).Count 1              'expired credentials are a death'

Write-Host "not deaths"
# A 500 is transient. Failing over on one would spend a fallback that a retry
# would not have needed.
Assert-Eq (@(Get-DeathLines 'Error: 500: {"message":"internal"}')).Count 0 'a 5xx is not a failover trigger'
Assert-Eq (@(Get-DeathLines 'Error: ENOENT: no such file or directory')).Count 0 'an ordinary tool error is not a death'
Assert-Eq (@(Get-DeathLines '')).Count 0    'empty output is not a death'
Assert-Eq (@(Get-DeathLines $null)).Count 0 'null output is not a death'

Write-Host "the brief is echoed into the same buffer"
# This is the false positive that matters: the ticket text sits in the pane
# output, so a keyword search would kill a perfectly healthy session on the
# strength of its own instructions.
$briefEcho = @"
 Task

 Handle the 429 rate limit path: when the upstream quota is exhausted, retry
 with backoff. Add a test that an expired credential surfaces to the user.

 Ran for 12s
"@
Assert-Eq (@(Get-DeathLines $briefEcho)).Count 0 'a brief about quotas and rate limits is not a death'

$mixed = $briefEcho + "`n Error: 402: out of credits`n"
Assert-Eq (@(Get-DeathLines $mixed)).Count 1 'a real error alongside that brief is still found'

Write-Host "multiple deaths"
# Wait-Agent compares counts against a baseline, so every occurrence has to be
# counted, not just the first.
$two = "Error: 402: no credits`nworking...`nError: 429: slow down`n"
$twoHits = @(Get-DeathLines $two)
Assert-Eq $twoHits.Count 2          'both deaths counted'
Assert-Eq $twoHits[1].Code '429'    'the latest death is last'

Write-Host ""
if ($failures -gt 0) { Write-Host "$failures failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "all passed" -ForegroundColor Green
