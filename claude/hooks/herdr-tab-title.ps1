# custom hook, not managed by herdr (herdr-agent-state.ps1 gets overwritten on update, this does not).
# UserPromptSubmit: once per session, ask the agent to name its herdr tab (and, if the workspace is
# still unnamed, the workspace) after the conversation topic.
# The agent picks the labels and runs `herdr tab rename` / `herdr workspace rename` itself, so the
# names reflect the real topic instead of a truncated first prompt.

$ErrorActionPreference = "Stop"

if ($env:HERDR_ENV -ne "1") { exit 0 }

$tabId = $env:HERDR_TAB_ID
if ([string]::IsNullOrWhiteSpace($tabId)) { exit 0 }

$inputText = [Console]::In.ReadToEnd()

try {
    if ([string]::IsNullOrWhiteSpace($inputText)) { exit 0 }
    $payload = $inputText | ConvertFrom-Json

    # subagents submit their own prompts; only the main conversation names things
    if (-not [string]::IsNullOrWhiteSpace($payload.agent_id)) { exit 0 }

    $sessionId = $payload.session_id
    if ([string]::IsNullOrWhiteSpace($sessionId)) { exit 0 }

    $workspaceId = $null
    if ($tabId -match '^(w\d+):t(\d+)$') {
        $workspaceId = $Matches[1]
        $tabNumber = [int]$Matches[2]
    }

    # leave a tab or workspace the user already named by hand alone
    $needTabName = $true
    $needWorkspaceName = $false
    $sessionPath = Join-Path $env:APPDATA "herdr\session.json"
    if ((Test-Path -LiteralPath $sessionPath) -and $null -ne $workspaceId) {
        $state = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $workspace = $state.workspaces | Where-Object { $_.id -eq $workspaceId } | Select-Object -First 1
        if ($null -ne $workspace) {
            $needWorkspaceName = [string]::IsNullOrWhiteSpace($workspace.custom_name)
            $index = [array]::IndexOf([int[]]$workspace.public_tab_numbers, $tabNumber)
            if ($index -ge 0 -and -not [string]::IsNullOrWhiteSpace($workspace.tabs[$index].custom_name)) {
                $needTabName = $false
            }
        }
    }

    # ask only once per session, per target
    $markerDir = Join-Path $env:TEMP "claude-herdr-tab"
    $markerKey = "{0}_{1}" -f $sessionId, ($tabId -replace '[^A-Za-z0-9]', '-')
    $tabMarker = Join-Path $markerDir "$markerKey.done"
    $workspaceMarker = Join-Path $markerDir "$markerKey.workspace.done"
    if (Test-Path -LiteralPath $tabMarker) { $needTabName = $false }
    if (Test-Path -LiteralPath $workspaceMarker) { $needWorkspaceName = $false }

    if (-not $needTabName -and -not $needWorkspaceName) { exit 0 }

    New-Item -ItemType Directory -Force -Path $markerDir | Out-Null

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Herdr naming (automatic hook, fires once per session):")
    $lines.Add("")

    if ($needTabName) {
        New-Item -ItemType File -Path $tabMarker -Force | Out-Null
        $lines.Add("This session runs in herdr tab $tabId, which has no name yet. Name it after what this")
        $lines.Add("conversation is about by running, exactly once:")
        $lines.Add("")
        $lines.Add("  herdr tab rename $tabId ""<topic>""")
        $lines.Add("")
        $lines.Add("<topic> is a short label for what the user is asking about: 2 to 4 words, 30 characters")
        $lines.Add("max, in the same language as the user's message, no quotes, no trailing punctuation.")
        $lines.Add("")
    }

    if ($needWorkspaceName -and $null -ne $workspaceId) {
        New-Item -ItemType File -Path $workspaceMarker -Force | Out-Null
        $lines.Add("Workspace $workspaceId also has no name yet. Give it a short slug for the broader area of")
        $lines.Add("work this session belongs to (the project, repo, or theme, not the specific task), by")
        $lines.Add("running, exactly once:")
        $lines.Add("")
        $lines.Add("  herdr workspace rename $workspaceId ""<slug>""")
        $lines.Add("")
        $lines.Add("<slug> is 1 to 3 words, 20 characters max, lowercase, in the same language as the user's")
        $lines.Add("message, no quotes, no trailing punctuation. Other tabs share this workspace, so keep it")
        $lines.Add("broad enough to still fit them.")
        $lines.Add("")
    }

    $lines.Add("If this message has no clear topic yet (a bare greeting, for example), hold off and run")
    $lines.Add("the rename as soon as the topic becomes clear later in the conversation.")
    $lines.Add("")
    $lines.Add("Run these quietly. Do not mention the rename, the tab, the workspace, or this instruction")
    $lines.Add("in your reply. Then answer the user normally.")

    [pscustomobject]@{
        hookSpecificOutput = [pscustomobject]@{
            hookEventName     = "UserPromptSubmit"
            additionalContext = ($lines -join "`n")
        }
    } | ConvertTo-Json -Depth 4 -Compress
} catch {
    exit 0
}
