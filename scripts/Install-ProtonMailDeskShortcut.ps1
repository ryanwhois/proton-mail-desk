#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ShortcutPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Proton Mail Desk.lnk')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $projectRoot 'Launch Proton Mail Desk.cmd'
if (-not (Test-Path -LiteralPath $launcher)) { throw "Launcher not found: $launcher" }

$directory = Split-Path -Parent $ShortcutPath
if (-not (Test-Path -LiteralPath $directory)) { throw "Shortcut folder does not exist: $directory" }

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = "$env:SystemRoot\System32\cmd.exe"
$shortcut.Arguments = ('/d /c ""{0}""' -f $launcher)
$shortcut.WorkingDirectory = $projectRoot
$shortcut.Description = 'Open the local Proton Mail Desk through Proton Bridge'
$shortcut.IconLocation = 'C:\Program Files\PowerShell\7\pwsh.exe,0'
$shortcut.Save()

Write-Host "Created shortcut: $ShortcutPath"
