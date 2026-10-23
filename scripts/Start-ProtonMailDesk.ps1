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

function Get-DeskWidth {
    try { $width = $Host.UI.RawUI.WindowSize.Width } catch { $width = 120 }
    return [Math]::Min(150, [Math]::Max(88, $width))
}

function Get-ClippedText {
    param([AllowNull()][string]$Text, [Parameter(Mandatory)][int]$Width)
    $singleLine = (($Text ?? '') -replace '[\r\n]+', ' ').Trim()
    if ($singleLine.Length -le $Width) { return $singleLine }
    if ($Width -le 1) { return $singleLine.Substring(0, $Width) }
    return $singleLine.Substring(0, $Width - 1) + '…'
}

function Write-DeskLine {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$Width)
    Write-Host ('| ' + (Get-ClippedText -Text $Text -Width ($Width - 4)).PadRight($Width - 4) + ' |')
}

function Write-DeskBorder {
    param([Parameter(Mandatory)][int]$Width)
    Write-Host ('+' + ('-' * ($Width - 2)) + '+')
}

function Show-MailList {
    param([Parameter(Mandatory)]$Result)
    $script:VisibleMessages = @($Result.emails)
    if ($script:VisibleMessages.Count -eq 0) { Write-Host 'No messages found.'; return }
    $width = Get-DeskWidth
    $senderWidth = [Math]::Min(38, [Math]::Max(26, [int]($width * 0.30)))
    $subjectWidth = $width - $senderWidth - 35
    $rowRule = '+' + ('-' * 4) + '+' + ('-' * 3) + '+' + ('-' * ($senderWidth + 2)) + '+' + ('-' * ($subjectWidth + 2)) + '+' + ('-' * 14) + '+' + ('-' * 3) + '+'
    $rowFormat = '| {0,2} | {1,-1} | {2,-' + $senderWidth + '} | {3,-' + $subjectWidth + '} | {4,-12} | {5,-1} |'

    Write-DeskBorder -Width $width
    Write-DeskLine -Width $width -Text ("PROTON MAIL DESK    {0}  ·  {1} shown of {2}" -f $Result.folder.ToUpperInvariant(), $script:VisibleMessages.Count, $Result.total)
    Write-DeskLine -Width $width -Text 'Choose a numbered message to read or organise it. * means unread; @ means attachment.'
    Write-DeskBorder -Width $width
    Write-Host $rowRule
    Write-Host ($rowFormat -f '#', '*', 'FROM', 'SUBJECT', 'RECEIVED', '@')
    Write-Host $rowRule
    for ($index = 0; $index -lt $script:VisibleMessages.Count; $index++) {
        $message = $script:VisibleMessages[$index]
        $sender = Get-ClippedText -Text (Get-AddressText $message.from) -Width $senderWidth
        $subject = Get-ClippedText -Text $message.subject -Width $subjectWidth
        $received = ([datetimeoffset]$message.date).ToLocalTime().ToString('dd MMM HH:mm')
        Write-Host ($rowFormat -f ($index + 1), $(if ($message.isRead) { '' } else { '*' }), $sender, $subject, $received, $(if ($message.hasAttachments) { '@' } else { '' }))
    }
    Write-Host $rowRule
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

function Add-WorkflowLabel {
    $message = Select-Message -Prompt 'Message number to label'
    if (-not $message) { return }

    Write-Host 'Choose a workflow state: [A] Action   [W] Waiting   [R] Read Later   [X] Cancel'
    $choice = Read-Host 'Label'
    if ($null -eq $choice) { return }
    $label = switch ($choice.Trim().ToUpperInvariant()) {
        'A' { 'Action' }
        'W' { 'Waiting' }
        'R' { 'Read Later' }
        'X' { return }
        default { Write-Host 'Choose A, W, R, or X.'; return }
    }

    if (-not (Confirm-Action "Add '$label' to '$($message.subject)'")) { return }
    $toolArguments = @{ labelsToAdd = @("Labels/$label") } | ConvertTo-Json -Compress
    Invoke-BridgeJson -Arguments @('update-message-labels', $message.id, '--args', $toolArguments, '--json') | Out-Null
    Write-Host "Added '$label'. The message remains in its current folder until you archive, move, or trash it."
    Refresh-Inbox
}

$script:VisibleMessages = @()
if (-not $NoInitialRefresh) { Refresh-Inbox }

while ($true) {
    $width = Get-DeskWidth
    Write-Host ''
    Write-DeskBorder -Width $width
    Write-DeskLine -Width $width -Text '[I] Inbox   [S] Search   [R] Read   [L] Label   [A] Archive   [T] Trash'
    Write-DeskLine -Width $width -Text '[M] Mark read   [C] Compose   [Q] Quit'
    Write-DeskBorder -Width $width
    $selection = Read-Host 'Choose'
    if ($null -eq $selection) { return }
    switch ($selection.Trim().ToUpperInvariant()) {
        'I' { Refresh-Inbox }
        'S' { Search-Mail }
        'R' { $message = Select-Message; if ($message) { Show-Message -Message $message } }
        'L' { Add-WorkflowLabel }
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
        default { Write-Host 'Choose I, S, R, L, A, T, M, C, or Q.' }
    }
}
