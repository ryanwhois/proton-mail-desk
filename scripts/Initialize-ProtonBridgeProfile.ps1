#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$ReadOnly,
    [switch]$Replace
)

Import-Module (Join-Path $PSScriptRoot 'ProtonAutomation.psm1') -Force
Save-ProtonBridgeProfile -ReadOnly:$ReadOnly -Replace:$Replace
Write-Host 'Local Bridge profile saved. It is encrypted for this Windows user and excluded from Git.'
