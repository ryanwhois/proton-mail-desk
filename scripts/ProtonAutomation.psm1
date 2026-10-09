Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:LocalDirectory = Join-Path $script:ProjectRoot '.local'
$script:ProfilePath = Join-Path $script:LocalDirectory 'bridge-profile.clixml'
$script:DataDirectory = Join-Path $script:LocalDirectory 'mail-data'
$script:ClientCli = Join-Path $script:ProjectRoot 'node_modules\proton-mail-bridge-client\dist\cli.js'
$script:ClientMcp = Join-Path $script:ProjectRoot 'node_modules\proton-mail-bridge-client\dist\index.js'

function Set-PrivateDirectory {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $Path /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not restrict access to $Path." }
}

function Save-ProtonBridgeProfile {
    [CmdletBinding()]
    param(
        [switch]$ReadOnly,
        [switch]$Replace
    )

    if ((Test-Path -LiteralPath $script:ProfilePath) -and -not $Replace) {
        throw 'A local Bridge profile already exists. Re-run with -Replace to update it.'
    }

    Set-PrivateDirectory -Path $script:LocalDirectory
    $username = Read-Host 'Proton Bridge mailbox username'
    if ([string]::IsNullOrWhiteSpace($username)) { throw 'A Bridge mailbox username is required.' }
    $password = Read-Host 'Proton Bridge mailbox password (not your Proton account password)' -AsSecureString
    if ($password.Length -eq 0) { throw 'A Bridge mailbox password is required.' }

    [pscustomobject]@{
        Username = $username.Trim()
        BridgePassword = $password
        ImapPort = 1143
        SmtpPort = 1025
        ReadOnly = [bool]$ReadOnly
        AllowSend = -not [bool]$ReadOnly
        ConfirmDestructive = $true
    } | Export-Clixml -LiteralPath $script:ProfilePath -Force
}

function Get-ProtonBridgeProfile {
    if (-not (Test-Path -LiteralPath $script:ProfilePath)) {
        throw 'No local Bridge profile exists. Run scripts/Initialize-ProtonBridgeProfile.ps1 in a normal PowerShell window.'
    }
    $profile = Import-Clixml -LiteralPath $script:ProfilePath
    if ($null -eq $profile -or [string]::IsNullOrWhiteSpace($profile.Username) -or $profile.BridgePassword -isnot [securestring]) {
        throw 'The local Bridge profile is invalid. Re-run scripts/Initialize-ProtonBridgeProfile.ps1 -Replace.'
    }
    return $profile
}

function Test-ProtonBridgeEndpoint {
    param([Parameter(Mandatory)][int]$Port)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $connect.Wait(3000)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Assert-ProtonBridgeReady {
    if (-not (Test-Path -LiteralPath $script:ClientCli)) {
        throw 'The local Proton client dependency is missing. Run npm.cmd ci from the repository root.'
    }
    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw 'Node.js is required but node.exe was not found.' }
    foreach ($port in 1143, 1025) {
        if (-not (Test-ProtonBridgeEndpoint -Port $port)) {
            throw "Proton Bridge is not responding on 127.0.0.1:$port. Start and sign in to Proton Mail Bridge, then retry."
        }
    }
}

function Invoke-WithProtonEnvironment {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [switch]$RequireWriteAccess
    )

    Assert-ProtonBridgeReady
    $profile = Get-ProtonBridgeProfile
    if ($RequireWriteAccess -and $profile.ReadOnly) {
        throw 'This local profile is read-only. Re-run Initialize-ProtonBridgeProfile.ps1 -Replace without -ReadOnly.'
    }

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($profile.BridgePassword)
    try {
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $old = @{}
        $values = @{
            PROTONMAIL_USERNAME = $profile.Username
            PROTONMAIL_PASSWORD = $plainPassword
            PROTONMAIL_IMAP_HOST = '127.0.0.1'
            PROTONMAIL_IMAP_PORT = [string]$profile.ImapPort
            PROTONMAIL_IMAP_SECURE = 'false'
            PROTONMAIL_SMTP_HOST = '127.0.0.1'
            PROTONMAIL_SMTP_PORT = [string]$profile.SmtpPort
            PROTONMAIL_SMTP_SECURE = 'false'
            PROTONMAIL_READ_ONLY = ([bool]$profile.ReadOnly).ToString().ToLowerInvariant()
            PROTONMAIL_ALLOW_SEND = ([bool]$profile.AllowSend).ToString().ToLowerInvariant()
            PROTONMAIL_CONFIRM_DESTRUCTIVE = ([bool]$profile.ConfirmDestructive).ToString().ToLowerInvariant()
            PROTONMAIL_TOOL_TIER = 'full'
            PROTONMAIL_ALLOW_REMOTE_DRAFT_SYNC = 'true'
            # Keep background index activity opt-in. A user can run `sync` when wanted;
            # this avoids a long mailbox scan and noisy stale-lock recovery on MCP startup.
            PROTONMAIL_STARTUP_SYNC = 'false'
            PROTONMAIL_AUTO_SYNC = 'false'
            PROTONMAIL_IDLE_WATCH = 'false'
            PROTONMAIL_DATA_DIR = $script:DataDirectory
        }
        foreach ($key in $values.Keys) { $old[$key] = [Environment]::GetEnvironmentVariable($key, 'Process'); [Environment]::SetEnvironmentVariable($key, $values[$key], 'Process') }
        & $Action
    } finally {
        foreach ($key in $old.Keys) { [Environment]::SetEnvironmentVariable($key, $old[$key], 'Process') }
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
}

function Invoke-ProtonClient {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$RequireWriteAccess)
    Invoke-WithProtonEnvironment -RequireWriteAccess:$RequireWriteAccess -Action { & node.exe $script:ClientCli @Arguments; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
}

function Start-ProtonMcpServer {
    Invoke-WithProtonEnvironment -RequireWriteAccess -Action { & node.exe $script:ClientMcp; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
}

Export-ModuleMember -Function Save-ProtonBridgeProfile, Get-ProtonBridgeProfile, Assert-ProtonBridgeReady, Invoke-ProtonClient, Start-ProtonMcpServer
