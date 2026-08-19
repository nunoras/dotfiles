#Requires -Version 7
<#
Records what herdr hands a link handler. Ctrl+click things in a pane, then read
the log to find out which of them herdr treats as a link at all.
#>
$ErrorActionPreference = 'Stop'

$logDir = if ($env:HERDR_PLUGIN_STATE_DIR) { $env:HERDR_PLUGIN_STATE_DIR } else { $PSScriptRoot }
$log = Join-Path $logDir 'probe.log'

$entry = [ordered]@{
    at              = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    clicked_url     = $env:HERDR_PLUGIN_CLICKED_URL
    link_handler_id = $env:HERDR_PLUGIN_LINK_HANDLER_ID
    action_id       = $env:HERDR_PLUGIN_ACTION_ID
    context         = $env:HERDR_PLUGIN_CONTEXT_JSON
}

($entry | ConvertTo-Json -Depth 4 -Compress) | Add-Content -LiteralPath $log
