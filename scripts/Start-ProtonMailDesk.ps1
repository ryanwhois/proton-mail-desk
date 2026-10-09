#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(5, 50)][int]$Limit = 15,
    [switch]$NoInitialRefresh
)

$ErrorActionPreference = 'Stop'
$invoke = Join-Path $PSScriptRoot 'Invoke-ProtonMail.ps1'

function Invoke-BridgeJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $raw = & $invoke @Arguments 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Proton Bridge command failed. Run npm.cmd run doctor for connection details.' }
    try { $response = $raw | ConvertFrom-Json -Depth 20 } catch { throw 'Proton Bridge returned an unexpected response.' }
    if ($response.content -and $response.content.Count -gt 0 -and $response.content[0].text) {
        try { return $response.content[0].text | ConvertFrom-Json -Depth 20 } catch { return $response.content[0].text }
    }
    return $response
}

function Get-AddressText {
    param($Addresses)
    if ($null -eq $Addresses) { return '' }
    return (($Addresses | ForEach-Object { if ($_.name) { "{0} <{1}>" -f $_.name, $_.address } else { $_.address } }) -join '; ')
}

function Show-MailList {
    param([Parameter(Mandatory)]$Result)
    $script:VisibleMessages = @($Result.emails)
    if ($script:VisibleMessages.Count -eq 0) { Write-Host 'No messages found.'; return }
    $rows = for ($index = 0; $index -lt $script:VisibleMessages.Count; $index++) {
        $message = $script:VisibleMessages[$index]
        [pscustomobject]@{
            '#' = $index + 1
            New = if ($message.isRead) { '' } else { '*' }
            From = (Get-AddressText $message.from)
            Subject = $message.subject
            When = ([datetimeoffset]$message.date).ToLocalTime().ToString('ddd HH:mm')
            Attachments = if ($message.hasAttachments) { 'yes' } else { '' }
        }
    }
    $rows | Format-Table -AutoSize | Out-Host
    Write-Host ("Showing {0} of {1} messages in {2}. * = unread." -f $script:VisibleMessages.Count, $Result.total, $Result.folder)
}

function Select-Message {
    param([string]$Prompt = 'Message number')
    if ($script:VisibleMessages.Count -eq 0) { Write-Host 'Refresh or search first.'; return $null }
    $choice = Read-Host $Prompt
    $number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $script:VisibleMessages.Count) {
        Write-Host 'Choose a message number from the displayed list.'
        return $null
    }
    return $script:VisibleMessages[$number - 1]
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Prompt)
    return (Read-Host "$Prompt [y/N]") -match '^(?i:y|yes)$'
}

function Show-Message {
    param([Parameter(Mandatory)]$Message)
    $detail = Invoke-BridgeJson -Arguments @('read', $Message.id, '--json')
    Write-Host ''
    Write-Host ('From:    ' + (Get-AddressText $detail.from))
    Write-Host ('To:      ' + (Get-AddressText $detail.to))
    Write-Host ('Subject: ' + $detail.subject)
    Write-Host ('Date:    ' + $detail.date)
    Write-Host ('-' * 72)
    if ($detail.text) { Write-Host $detail.text } elseif ($detail.body) { Write-Host $detail.body } else { Write-Host 'No plain-text body was returned.' }
    Write-Host ('-' * 72)
}

function Refresh-Inbox {
    $result = Invoke-BridgeJson -Arguments @('emails', '--folder', 'INBOX', '--limit', $Limit, '--json')
    Show-MailList -Result $result
}

function Search-Mail {
    $query = Read-Host 'Search words, sender, or subject'
    if ([string]::IsNullOrWhiteSpace($query)) { return }
    $result = Invoke-BridgeJson -Arguments @('search', $query, '--live', '--limit', $Limit, '--json')
    Show-MailList -Result $result
}

$script:VisibleMessages = @()
Write-Host 'Proton Mail Desk — local Bridge mailbox assistant'
Write-Host 'Read/search operations do not change messages. Archive and Trash always ask first; sending requires a second confirmation.'
if (-not $NoInitialRefresh) { Refresh-Inbox }

while ($true) {
    Write-Host ''
    Write-Host '[I]nbox  [S]earch  [R]ead  [A]rchive  [T]rash  [M]ark read  [C]ompose  [Q]uit'
    $selection = Read-Host 'Choose'
    if ($null -eq $selection) { return }
    switch ($selection.Trim().ToUpperInvariant()) {
        'I' { Refresh-Inbox }
        'S' { Search-Mail }
        'R' { $message = Select-Message; if ($message) { Show-Message -Message $message } }
        'A' {
            $message = Select-Message
            if ($message -and (Confirm-Action "Archive '$($message.subject)'")) {
                Invoke-BridgeJson -Arguments @('archive', $message.id, '--json') | Out-Null
                Write-Host 'Archived.'; Refresh-Inbox
            }
        }
        'T' {
            $message = Select-Message
            if ($message -and (Confirm-Action "Move '$($message.subject)' to Trash")) {
                Invoke-BridgeJson -Arguments @('trash', $message.id, '--json') | Out-Null
                Write-Host 'Moved to Trash.'; Refresh-Inbox
            }
        }
        'M' {
            $message = Select-Message
            if ($message) {
                Invoke-BridgeJson -Arguments @('mark-read', $message.id, '--json') | Out-Null
                Write-Host 'Marked as read.'; Refresh-Inbox
            }
        }
        'C' {
            $to = Read-Host 'To'
            $subject = Read-Host 'Subject'
            $body = Read-Host 'Message (one line)'
            if ([string]::IsNullOrWhiteSpace($to) -or [string]::IsNullOrWhiteSpace($subject)) { Write-Host 'Recipient and subject are required.'; break }
            Write-Host "About to send to $to with subject: $subject"
            if (Confirm-Action 'Send this message') {
                Invoke-BridgeJson -Arguments @('-ConfirmDestructive', 'send', '--to', $to, '--subject', $subject, '--body', $body, '--json') | Out-Null
                Write-Host 'Message sent.'
            }
        }
        'Q' { return }
        default { Write-Host 'Choose I, S, R, A, T, M, C, or Q.' }
    }
}
