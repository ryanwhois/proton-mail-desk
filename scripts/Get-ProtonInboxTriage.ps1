#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1, 60)][int]$Days = 14,
    [ValidateRange(50, 100)][int]$PageSize = 100,
    [ValidateRange(100, 5000)][int]$MaxMessages = 1000,
    [switch]$IncludeMessages,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-ProtonEmailResponse {
    param([Parameter(Mandatory)][string]$RawResponse)

    $response = $RawResponse | ConvertFrom-Json
    if ($null -ne $response.PSObject.Properties['emails']) {
        return $response
    }

    $contentProperty = $response.PSObject.Properties['content']
    if ($null -eq $contentProperty) {
        throw 'The Proton client response did not contain email data.'
    }

    $text = @($contentProperty.Value | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'The Proton client did not return an email-list payload.'
    }

    return $text | ConvertFrom-Json
}

function Get-ReviewSignal {
    param([Parameter(Mandatory)]$Message)

    $subject = [string]$Message.subject
    if ($subject -match '(?i)\b(verification code|one[- ]time code|security alert|security profile|oauth .* (added|application)|please review this sign[ -]?in|password is expiring)\b') {
        return 'Security or account access'
    }
    if ($subject -match '(?i)\b(inkasso|final notice before debt collection|payment overdue|faktura|invoice|payment (to|on|due)|betaling|digital post|aftale .*dans?ke bank|confirm tax info)\b') {
        return 'Financial or official'
    }
    if ($subject -match '(?i)\b(meeting|calendar|interview|upload cv|application|job|møde)\b') {
        return 'Work or calendar'
    }
    if ($subject -match '(?i)\b(delivered|dispatched|parcel|package|pakke|hente pakke|order receipt)\b') {
        return 'Delivery or order'
    }
    return $null
}

function Get-MessageSender {
    param([Parameter(Mandatory)]$Message)

    $fromProperty = $Message.PSObject.Properties['from']
    if ($null -eq $fromProperty) { return '(no sender name)' }

    $firstSender = @($fromProperty.Value | Select-Object -First 1)[0]
    if ($null -eq $firstSender) { return '(no sender name)' }

    $nameProperty = $firstSender.PSObject.Properties['name']
    if ($null -ne $nameProperty -and -not [string]::IsNullOrWhiteSpace($nameProperty.Value)) {
        return [string]$nameProperty.Value
    }

    return '(no sender name)'
}

function Get-MessageAddress {
    param([Parameter(Mandatory)]$Message)

    $fromProperty = $Message.PSObject.Properties['from']
    if ($null -eq $fromProperty) { return $null }

    $firstSender = @($fromProperty.Value | Select-Object -First 1)[0]
    if ($null -eq $firstSender) { return $null }

    $addressProperty = $firstSender.PSObject.Properties['address']
    if ($null -eq $addressProperty) { return $null }
    return [string]$addressProperty.Value
}

function ConvertTo-TriageHeader {
    param([Parameter(Mandatory)]$Message)

    return [pscustomobject]@{
        EmailId = [string]$Message.id
        Date = ([datetime]$Message.date).ToString('o')
        Sender = Get-MessageSender -Message $Message
        SenderAddress = Get-MessageAddress -Message $Message
        Subject = [string]$Message.subject
        IsRead = [bool]$Message.isRead
        IsStarred = [bool]$Message.isStarred
        HasAttachments = [bool]$Message.hasAttachments
    }
}

$cutoff = (Get-Date).Date.AddDays(-$Days)
$allMessages = [System.Collections.Generic.List[object]]::new()
$offset = 0
$hasReachedCutoff = $false
$invokeScript = Join-Path $PSScriptRoot 'Invoke-ProtonMail.ps1'

while ($allMessages.Count -lt $MaxMessages -and -not $hasReachedCutoff) {
    $raw = (& $invokeScript emails --folder INBOX --limit $PageSize --offset $offset --json | Out-String)
    $page = ConvertFrom-ProtonEmailResponse -RawResponse $raw
    $pageMessages = @($page.emails)
    if ($pageMessages.Count -eq 0) { break }

    foreach ($message in $pageMessages) {
        $allMessages.Add($message)
    }

    $oldestOnPage = [datetime]$pageMessages[-1].date
    $hasReachedCutoff = $oldestOnPage -lt $cutoff
    if ($pageMessages.Count -lt $PageSize) { break }
    $offset += $pageMessages.Count
}

$messages = @(
    $allMessages |
        Where-Object { ([datetime]$_.date) -ge $cutoff } |
        Sort-Object date -Descending
)

$senderSummary = @(
    $messages |
        Group-Object { Get-MessageSender -Message $_ } |
        Sort-Object Count -Descending |
        ForEach-Object {
            [pscustomobject]@{
                Sender = $_.Name
                Messages = $_.Count
                Unread = @($_.Group | Where-Object { -not $_.isRead }).Count
                Starred = @($_.Group | Where-Object isStarred).Count
                Latest = ([datetime](($_.Group | Sort-Object date -Descending | Select-Object -First 1).date)).ToString('yyyy-MM-dd')
            }
        }
)

$reviewItems = @(
    foreach ($message in $messages) {
        $signal = Get-ReviewSignal -Message $message
        if ($null -ne $signal) {
            [pscustomobject]@{
                Date = ([datetime]$message.date).ToString('yyyy-MM-dd HH:mm')
                Signal = $signal
                Sender = Get-MessageSender -Message $message
                Unread = -not $message.isRead
                Starred = [bool]$message.isStarred
                Subject = $message.subject
            }
        }
    }
)

$result = [pscustomobject]@{
    ReadOnly = $true
    WindowStart = $cutoff.ToString('yyyy-MM-dd')
    WindowEnd = (Get-Date).ToString('yyyy-MM-dd')
    HeadersExamined = $allMessages.Count
    ReachedWindowStart = $hasReachedCutoff
    MessageCount = $messages.Count
    UnreadCount = @($messages | Where-Object { -not $_.isRead }).Count
    StarredCount = @($messages | Where-Object isStarred).Count
    SenderCount = $senderSummary.Count
    Senders = $senderSummary
    ReviewItems = $reviewItems
    Headers = if ($IncludeMessages) { @($messages | ForEach-Object { ConvertTo-TriageHeader -Message $_ }) } else { @() }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Write-Host ''
Write-Host 'Proton Inbox triage (read-only)' -ForegroundColor Cyan
Write-Host ("Window: {0} through {1}" -f $result.WindowStart, $result.WindowEnd)
Write-Host ("Messages: {0} total, {1} unread, {2} starred, from {3} senders" -f $result.MessageCount, $result.UnreadCount, $result.StarredCount, $result.SenderCount)
Write-Host ("Headers examined: {0}; full window retrieved: {1}" -f $result.HeadersExamined, $result.ReachedWindowStart)
Write-Host 'No messages, labels, folders, or read states were changed.' -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Highest-volume senders' -ForegroundColor Cyan
$result.Senders | Select-Object -First 20 | Format-Table -AutoSize

Write-Host ''
Write-Host 'Messages that need individual review before a bulk action' -ForegroundColor Cyan
if ($result.ReviewItems.Count -eq 0) {
    Write-Host 'None matched the security, official/financial, work/calendar, or delivery/order signals.'
} else {
    $result.ReviewItems | Format-Table -Wrap -AutoSize
}
