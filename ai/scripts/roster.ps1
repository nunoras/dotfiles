# Roster helpers - single source of truth for role -> model, and harness routing.
#
# Dot-source this: . "$HOME\.claude\scripts\roster.ps1"
#
# The roster itself lives in ai/roster.json (symlinked to ~/.claude/roster.json).
# Model refs are written "provider:id". The id may contain slashes
# (openrouter:z-ai/glm-5.3), so refs split on the FIRST colon only.
#
# Keep PowerShell 5.1 compatible: herdr spawns Windows PowerShell 5.1.
# No ??, no ?., no ternary.

function Get-RosterScriptDir {
    # $PSScriptRoot may itself be a directory symlink (~/.claude/scripts ->
    # ai/scripts). In that case its parent is ~/.claude, not the repo, so resolve
    # the link to the real ai/scripts before walking up to roster.json.
    $item = Get-Item -LiteralPath $PSScriptRoot -Force -ErrorAction SilentlyContinue
    if ($item -and $item.Target) {
        $target = @($item.Target)[0]
        if ($target) { return $target }
    }
    return $PSScriptRoot
}

function Get-RosterPath {
    # Prefer the real ai/roster.json (resolving the scripts symlink), then a
    # ~/.claude/roster.json symlink if one exists, so it works from any path.
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
    $entry = $roster.$Role
    if (-not $entry) { throw "unknown role '$Role' (roles: $(($roster.PSObject.Properties.Name) -join ', '))" }
    return [pscustomobject]@{
        Role     = $Role
        Primary  = $entry.primary
        Fallback = $entry.fallback
    }
}

function Get-Harness {
    # The one rule: anthropic -> Claude Code, everything else -> pi.
    param([Parameter(Mandatory)][string]$Provider)
    if ($Provider -eq 'anthropic') { return 'claude' }
    return 'pi'
}

function Split-ModelRef {
    # "provider:id" -> @{ Provider; Model }. Splits on the first colon only.
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

function Get-RoleHarness {
    # Convenience: role -> harness of its primary model.
    param(
        [Parameter(Mandatory)][string]$Role,
        [string]$Path
    )
    $entry = Get-RosterEntry -Role $Role -Path $Path
    return (Get-Harness -Provider (Split-ModelRef $entry.Primary).Provider)
}
