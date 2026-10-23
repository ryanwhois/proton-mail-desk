#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1, 60)][int]$Days = 14,
    [string]$OutputPath = (Join-Path $PSScriptRoot ("..\.local\reports\Inbox-Decision-Worksheet-{0}.md" -f (Get-Date -Format 'yyyy-MM-dd-HHmmss'))),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-MarkdownCell {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '—' }
    return $Text.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Get-DefaultChoice {
    param([Parameter(Mandatory)]$Proposal)

    $action = [string]$Proposal.SuggestedAction
    if ($action -like '*Labels/Read Later*') { return 'R' }
    if ($action -eq 'Archive') { return 'X' }
    if ($action -like 'Leave unread; star*') { return 'HS' }
    if ($action -like 'Leave unread; manual*') { return 'H' }
    if ($action -like '*Labels/Action*') { return 'A' }
    return 'Q'
}

function Get-MailState {
    param([Parameter(Mandatory)]$Proposal)

    $state = [System.Collections.Generic.List[string]]::new()
    if ($Proposal.IsRead) { $state.Add('read') } else { $state.Add('unread') }
    if ($Proposal.IsStarred) { $state.Add('starred') }
    if ($Proposal.HasAttachments) { $state.Add('attachment') }
    return $state -join ', '
}

$proposalScript = Join-Path $PSScriptRoot 'Get-ProtonMailActionProposals.ps1'
$report = (& $proposalScript -Days $Days -Json | ConvertFrom-Json)
if (-not $report.ReadOnly) {
    throw 'The proposal source did not report itself as read-only.'
}

$manualProposals = @($report.Proposals | Where-Object NeedsReview)
$readyProposals = @($report.Proposals | Where-Object { -not $_.NeedsReview })
$manualGroups = @(
    $manualProposals |
        Group-Object { "{0}|{1}|{2}|{3}|{4}" -f $_.Date, $_.Sender, $_.Subject, $_.Rule, $_.SuggestedAction } |
        Sort-Object { [datetime]$_.Group[0].Date } -Descending
)

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Proton Mail decision worksheet')
$lines.Add('')
$lines.Add(("Generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')))
$lines.Add(("Review window: {0} through {1}" -f $report.WindowStart, $report.WindowEnd))
$lines.Add(("Header-only review: {0} messages examined; {1} manual decisions grouped into {2} worksheet items." -f $report.MessagesExamined, $manualProposals.Count, $manualGroups.Count))
$lines.Add('')
$lines.Add('This file contains local mailbox metadata and is stored under `.local`, which is ignored by Git. It does not contain message bodies and creating it does not change any mail.')
$lines.Add('')
$lines.Add('## Choice key')
$lines.Add('')
$lines.Add('| Choice | Final Zero-Inbox disposition |')
$lines.Add('| --- | --- |')
$lines.Add('| `A` | Add `Action`, then archive. |')
$lines.Add('| `W` | Add `Waiting`, then archive. |')
$lines.Add('| `R` | Add `Read Later`, then archive. |')
$lines.Add('| `X` | Mark read, then archive; no further action. |')
$lines.Add('| `I` | Mark read, then move to `Invoices`. |')
$lines.Add('| `C` | Mark read, then move to `Receipts`. |')
$lines.Add('| `T` | Move to Trash; a final confirmation will still be required. |')
$lines.Add('| `U` | Add an occasional unsubscribe reminder; choose another disposition for the current message. |')
$lines.Add('| `H` | Temporary hold: leave unread in Inbox, optionally starred; not a final Zero-Inbox state. |')
$lines.Add('| `Q` | Request a message preview or further question before deciding. |')
$lines.Add('')
$lines.Add('A star is an optional modifier, not a final disposition: for example, `AS` means Action plus star, and `HS` means temporary hold plus star.')
$lines.Add('')
$lines.Add('## Policy-ready batch, pending final approval')
$lines.Add('')
$lines.Add(("The current policy proposes {0} messages for a final, separately confirmed batch: {1} archive candidates and {2} Read Later-plus-archive candidates." -f $report.ReadyForReviewCount, @($readyProposals | Where-Object { $_.SuggestedAction -eq 'Archive' }).Count, @($readyProposals | Where-Object { $_.SuggestedAction -like '*Labels/Read Later*' }).Count))
$lines.Add('')
$lines.Add('Inspect the exact headers below. The blank column is optional: leave it blank to preserve the policy default, or enter `H` or `Q` to withhold an item from the eventual batch.')
$lines.Add('')
$lines.Add('| Batch item | Received | Sender | Subject | Current state | Policy default | Hold / question |')
$lines.Add('| --- | --- | --- | --- | --- | --- | --- |')

$batchItem = 0
foreach ($proposal in ($readyProposals | Sort-Object { [datetime]$_.Date } -Descending)) {
    $batchItem++
    $received = ([datetime]$proposal.Date).ToString('yyyy-MM-dd HH:mm')
    $lines.Add(("| B{0:D2} | {1} | {2} | {3} | {4} | `{5}` |  |" -f $batchItem, (ConvertTo-MarkdownCell $received), (ConvertTo-MarkdownCell $proposal.Sender), (ConvertTo-MarkdownCell $proposal.Subject), (ConvertTo-MarkdownCell (Get-MailState -Proposal $proposal)), (Get-DefaultChoice -Proposal $proposal)))
}
$lines.Add('')
$lines.Add('## Decisions needed')
$lines.Add('')
$lines.Add('Fill the final column with one choice code. Duplicates are grouped only when their timestamp, sender, subject, rule, and suggested action all match.')
$lines.Add('')
$lines.Add('| Item | Received | Sender | Subject | Current state | Why shown | Default | Your choice |')
$lines.Add('| --- | --- | --- | --- | --- | --- | --- | --- |')

$item = 0
foreach ($group in $manualGroups) {
    $item++
    $proposal = $group.Group[0]
    $copySuffix = if ($group.Count -gt 1) { " (copies: $($group.Count))" } else { '' }
    $received = ([datetime]$proposal.Date).ToString('yyyy-MM-dd HH:mm')
    $reason = "{0}; {1}" -f $proposal.Rule, $proposal.Notes
    $lines.Add(("| M{0:D2} | {1} | {2} | {3}{4} | {5} | {6} | `{7}` |  |" -f $item, (ConvertTo-MarkdownCell $received), (ConvertTo-MarkdownCell $proposal.Sender), (ConvertTo-MarkdownCell $proposal.Subject), $copySuffix, (ConvertTo-MarkdownCell (Get-MailState -Proposal $proposal)), (ConvertTo-MarkdownCell $reason), (Get-DefaultChoice -Proposal $proposal)))
}

$lines.Add('')
$lines.Add('## How to respond')
$lines.Add('')
$lines.Add('Reply in chat with entries such as `M01 H`, `M02 AS`, and `M03 I`, or edit the **Your choice** cells and paste the completed rows. I will update the policy and regenerate a read-only proposal report before any mail-changing command is considered.')

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    throw "Worksheet already exists: $OutputPath. Re-run with -Force to replace it."
}

[System.IO.File]::WriteAllLines($OutputPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Output $OutputPath
