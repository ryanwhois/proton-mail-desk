#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1, 60)][int]$Days = 14,
    [string]$PolicyPath = (Join-Path $PSScriptRoot '..\config\mail-policy.psd1'),
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-AnyPattern {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($Text -match $pattern) { return $true }
    }
    return $false
}

function Get-ProtectedCategory {
    param(
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][hashtable]$Patterns
    )

    foreach ($category in $Patterns.Keys) {
        if ($Subject -match $Patterns[$category]) { return [string]$category }
    }
    return $null
}

function New-Proposal {
    param(
        [Parameter(Mandatory)]$Message,
        [Parameter(Mandatory)][string]$Rule,
        [Parameter(Mandatory)][string]$SuggestedAction,
        [Parameter(Mandatory)][bool]$NeedsReview,
        [string]$Notes
    )

    return [pscustomobject]@{
        EmailId = $Message.EmailId
        Date = $Message.Date
        Sender = $Message.Sender
        Subject = $Message.Subject
        IsRead = [bool]$Message.IsRead
        IsStarred = [bool]$Message.IsStarred
        HasAttachments = [bool]$Message.HasAttachments
        Rule = $Rule
        SuggestedAction = $SuggestedAction
        NeedsReview = $NeedsReview
        Notes = $Notes
    }
}

if (-not (Test-Path -LiteralPath $PolicyPath)) {
    throw "Mail policy was not found: $PolicyPath"
}

$policy = Import-PowerShellDataFile -LiteralPath $PolicyPath
$triageScript = Join-Path $PSScriptRoot 'Get-ProtonInboxTriage.ps1'
$triage = (& $triageScript -Days $Days -IncludeMessages -Json | ConvertFrom-Json)
if (-not $triage.ReadOnly) {
    throw 'The source triage did not report itself as read-only.'
}
if (-not $triage.ReachedWindowStart) {
    throw 'The requested review window was not retrieved completely; no proposals were produced.'
}

$proposals = [System.Collections.Generic.List[object]]::new()
$messages = @($triage.Headers)

foreach ($senderGroup in ($messages | Group-Object Sender)) {
    $sender = [string]$senderGroup.Name
    $groupMessages = @($senderGroup.Group | Sort-Object { [datetime]$_.Date } -Descending)

    for ($index = 0; $index -lt $groupMessages.Count; $index++) {
        $message = $groupMessages[$index]
        $subject = [string]$message.Subject

        if ($policy.NewsletterSenders -contains $sender) {
            if ($index -eq 0) {
                $proposals.Add((New-Proposal -Message $message -Rule 'Newsletter retention' -SuggestedAction 'Add Labels/Read Later, then archive' -NeedsReview $false -Notes 'Newest edition for this sender.'))
            } else {
                $proposals.Add((New-Proposal -Message $message -Rule 'Newsletter retention' -SuggestedAction 'Archive' -NeedsReview $false -Notes 'Older edition for this sender; ask about unsubscribe occasionally.'))
            }
            continue
        }

        if ($sender -eq 'GitHub') {
            if (Test-AnyPattern -Text $subject -Patterns $policy.GitHubSecurityPatterns) {
                $proposals.Add((New-Proposal -Message $message -Rule 'GitHub security/access' -SuggestedAction 'Leave unread; manual review only' -NeedsReview $true -Notes 'Never batch-change account or access notices.'))
            } elseif (Test-AnyPattern -Text $subject -Patterns $policy.GitHubActionPatterns) {
                $proposals.Add((New-Proposal -Message $message -Rule 'GitHub build/deployment/error' -SuggestedAction 'Consider Labels/Action, then archive' -NeedsReview $true -Notes 'User requested a conservative review before choosing Action.'))
            } else {
                $proposals.Add((New-Proposal -Message $message -Rule 'GitHub non-security notification' -SuggestedAction 'Review, then choose Action, Read Later, or Archive' -NeedsReview $true -Notes 'No default folder or label has been approved.'))
            }
            continue
        }

        if ($sender -eq 'Revolut') {
            if (Test-AnyPattern -Text $subject -Patterns $policy.RevolutAccountPatterns) {
                $proposals.Add((New-Proposal -Message $message -Rule 'Revolut account/payment/card' -SuggestedAction 'Leave unread; star after individual review' -NeedsReview $true -Notes 'No batch change for financial/account mail.'))
            } elseif (Test-AnyPattern -Text $subject -Patterns $policy.RevolutPromotionPatterns) {
                $proposals.Add((New-Proposal -Message $message -Rule 'Revolut promotion' -SuggestedAction 'Add Labels/Read Later, then archive' -NeedsReview $true -Notes 'Confirm the message is promotional before applying the label.'))
            } else {
                $proposals.Add((New-Proposal -Message $message -Rule 'Revolut unclassified' -SuggestedAction 'Manual review only' -NeedsReview $true -Notes 'Neither promotional nor transactional pattern matched safely.'))
            }
            continue
        }

        $protectedCategory = Get-ProtectedCategory -Subject $subject -Patterns $policy.ProtectedPatterns
        if ($null -ne $protectedCategory) {
            $proposals.Add((New-Proposal -Message $message -Rule $protectedCategory -SuggestedAction 'Leave unchanged; review individually before star, folder, label, or archive' -NeedsReview $true -Notes 'The exact folder or Action condition has not been approved.'))
        }
    }
}

$result = [pscustomobject]@{
    ReadOnly = $true
    PolicyVersion = $policy.Version
    WindowStart = $triage.WindowStart
    WindowEnd = $triage.WindowEnd
    MessagesExamined = $triage.MessageCount
    ProposalCount = $proposals.Count
    ReadyForReviewCount = @($proposals | Where-Object { -not $_.NeedsReview }).Count
    NeedsReviewCount = @($proposals | Where-Object NeedsReview).Count
    Proposals = @($proposals | Sort-Object { [datetime]$_.Date } -Descending)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Write-Host ''
Write-Host 'Proton Mail action proposals (read-only)' -ForegroundColor Cyan
Write-Host ("Policy version: {0}; window: {1} through {2}" -f $result.PolicyVersion, $result.WindowStart, $result.WindowEnd)
Write-Host ("Messages examined: {0}; proposals: {1}; ready for review: {2}; manual review: {3}" -f $result.MessagesExamined, $result.ProposalCount, $result.ReadyForReviewCount, $result.NeedsReviewCount)
Write-Host 'No mailbox changes were made. Review the exact proposals before enabling any apply command.' -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Proposal summary' -ForegroundColor Cyan
$result.Proposals | Group-Object Rule, SuggestedAction | Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{
        Rule = $_.Group[0].Rule
        SuggestedAction = $_.Group[0].SuggestedAction
        Messages = $_.Count
        NeedsReview = $_.Group[0].NeedsReview
    }
} | Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host 'Exact proposals' -ForegroundColor Cyan
$result.Proposals | Format-Table Date, Sender, Rule, SuggestedAction, NeedsReview, Subject -Wrap -AutoSize
