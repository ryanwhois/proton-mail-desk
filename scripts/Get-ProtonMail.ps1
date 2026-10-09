#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$Folder = 'INBOX',
    [ValidateRange(1, 100)][int]$Limit = 25,
    [int]$Offset = 0,
    [switch]$Json
)

$arguments = @('emails', '--folder', $Folder, '--limit', $Limit, '--offset', $Offset)
if ($Json) { $arguments += '--json' }
& (Join-Path $PSScriptRoot 'Invoke-ProtonMail.ps1') @arguments
exit $LASTEXITCODE
