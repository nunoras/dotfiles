function Get-RosterScriptDir {
    $item = Get-Item -LiteralPath $PSScriptRoot -Force -ErrorAction SilentlyContinue
    if ($item -and $item.Target) {
        $target = @($item.Target)[0]
        if ($target) { return $target }
    }
    return $PSScriptRoot
}

function Get-RosterPath {
    $beside = Join-Path (Split-Path (Get-RosterScriptDir) -Parent) 'roster.json'
    if (Test-Path $beside) { return $beside }
    $claude = Join-Path $HOME '.claude\roster.json'
    if (Test-Path $claude) { return $claude }
    throw "roster.json not found (looked in $beside and $claude)"
}

function Get-Roster {
    param([string]$Path)
    if (-not $Path) { $Path = Get-RosterPath }
    return (Get-Content $Path -Raw | ConvertFrom-Json)
}

function Get-RosterEntry {
    param(
        [Parameter(Mandatory)][string]$Role,
        [string]$Path
    )
    $roster = Get-Roster -Path $Path
    if (-not $roster.roles) {
        throw "roster at '$Path' has no 'roles' object (expected the policy+roles schema; the old flat { primary, fallback } shape is gone)"
    }
    $entry = $null
    if (-not $Role.StartsWith('_') -and -not $Role.StartsWith('$')) { $entry = $roster.roles.$Role }
    if (-not $entry) {
        $roles = @($roster.roles.PSObject.Properties.Name | Where-Object { -not $_.StartsWith('_') -and -not $_.StartsWith('$') })
        throw "unknown role '$Role' (roles: $($roles -join ', '))"
    }
    return [pscustomobject]@{
        Role     = $Role
        Model    = $entry.model
        Fallback = $entry.fallback
    }
}

function Get-Harness {
    param([Parameter(Mandatory)][string]$Provider)
    switch ($Provider) {
        'anthropic' { return 'claude' }
        'codex'     { return 'codex' }
        'agy'       { return 'agy' }
        default     { return 'pi' }
    }
}

function Split-ModelRef {
    param([Parameter(Mandatory)][string]$Ref)
    $i = $Ref.IndexOf(':')
    if ($i -lt 1 -or $i -eq ($Ref.Length - 1)) {
        throw "model ref '$Ref' is not 'provider:id'"
    }
    return [pscustomobject]@{
        Provider = $Ref.Substring(0, $i)
        Model    = $Ref.Substring($i + 1)
    }
}

function Assert-ValidModelRef {
    param([Parameter(Mandatory)][string]$Ref)
    Split-ModelRef $Ref | Out-Null
}

function Assert-ValidFallbackChain {
    param([Parameter(Mandatory)][string]$Fallback)
    foreach ($f in ($Fallback -split ',')) {
        $f = $f.Trim()
        if ($f) { Assert-ValidModelRef $f }
    }
}

function Get-RosterFrontmatter {
    param(
        [Parameter(Mandatory)][string]$Role,
        [string]$Base = 'main',
        [string]$Path
    )
    $entry = Get-RosterEntry -Role $Role -Path $Path
    Assert-ValidModelRef $entry.Model
    $lines = @("role: $Role", "model: $($entry.Model)")
    if ($entry.Fallback) {
        Assert-ValidFallbackChain $entry.Fallback
        $lines += "fallbackModels: $($entry.Fallback)"
    }
    $lines += "base: $Base"
    return ($lines -join "`n")
}

function Get-RoleHarness {
    param(
        [Parameter(Mandatory)][string]$Role,
        [string]$Path
    )
    $entry = Get-RosterEntry -Role $Role -Path $Path
    return (Get-Harness -Provider (Split-ModelRef $entry.Model).Provider)
}
