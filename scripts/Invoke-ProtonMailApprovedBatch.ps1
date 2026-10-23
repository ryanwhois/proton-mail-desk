#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateRange(1, 60)][int]$Days = 14,
    [switch]$ConfirmApply,
    [string]$AuditPath = (Join-Path $PSScriptRoot ("..\.local\reports\Approved-Mail-Batch-{0}.json" -f (Get-Date -Format 'yyyy-MM-dd-HHmmss')))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ApprovedProposals {
    param([Parameter(Mandatory)]$Report)

    if (-not $Report.ReadOnly) {
        throw 'The proposal source did not report itself as read-only.'
    }

    $approved = @($Report.Proposals | Where-Object { -not $_.NeedsReview })
    $unexpected = @(
        $approved |
            Where-Object {
                $_.Rule -ne 'Newsletter retention' -or
                $_.SuggestedAction -notin @('Archive', 'Add Labels/Read Later, then archive')
            }
    )
    if ($unexpected.Count -gt 0) {
        throw "The live proposal report contained $($unexpected.Count) item(s) outside the approved newsletter batch. No changes were made."
    }

    return $approved
}

function Invoke-MailClient {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $invokeScript = Join-Path $PSScriptRoot 'Invoke-ProtonMail.ps1'
    $output = (& $invokeScript @Arguments | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Proton client command failed: $($Arguments -join ' ')`n$output"
    }
    return $output
}

$proposalScript = Join-Path $PSScriptRoot 'Get-ProtonMailActionProposals.ps1'
$report = (& $proposalScript -Days $Days -Json | ConvertFrom-Json)
$approved = Get-ApprovedProposals -Report $report
$archiveOnly = @($approved | Where-Object { $_.SuggestedAction -eq 'Archive' })
$readLaterThenArchive = @($approved | Where-Object { $_.SuggestedAction -eq 'Add Labels/Read Later, then archive' })

Write-Host ''
Write-Host 'Approved newsletter batch' -ForegroundColor Cyan
Write-Host ("Window: {0} through {1}" -f $report.WindowStart, $report.WindowEnd)
Write-Host ("{0} messages: {1} archive-only; {2} add Read Later then archive." -f $approved.Count, $archiveOnly.Count, $readLaterThenArchive.Count)
$approved | Select-Object Date, Sender, Subject, SuggestedAction | Format-Table -Wrap -AutoSize

if (-not $ConfirmApply) {
    Write-Host 'No changes made. Re-run with -ConfirmApply only after reviewing this exact live batch.' -ForegroundColor Yellow
    exit 0
}

$auditEntries = [System.Collections.Generic.List[object]]::new()
$parent = Split-Path -Parent $AuditPath
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

try {
    foreach ($proposal in $approved) {
        $id = [string]$proposal.EmailId
        $subject = [string]$proposal.Subject
        $action = [string]$proposal.SuggestedAction
        $entry = [ordered]@{
            EmailId = $id
            Date = $proposal.Date
            Sender = $proposal.Sender
            Subject = $subject
            Action = $action
            LabelApplied = $false
            Archived = $false
            Status = 'Pending'
        }

        if (-not $PSCmdlet.ShouldProcess($subject, $action)) {
            $entry.Status = 'WhatIf'
            $auditEntries.Add([pscustomobject]$entry)
            continue
        }

        if ($action -eq 'Add Labels/Read Later, then archive') {
            $labelArgs = @{ labelsToAdd = @('Labels/Read Later') } | ConvertTo-Json -Compress
            Invoke-MailClient -Arguments @('update-message-labels', $id, '--args', $labelArgs, '--json') | Out-Null
            $entry.LabelApplied = $true
        }

        Invoke-MailClient -Arguments @('archive', $id, '--json') | Out-Null
        $entry.Archived = $true
        $entry.Status = 'Applied'
        $auditEntries.Add([pscustomobject]$entry)
    }
} catch {
    if ($null -ne $entry) {
        $entry.Status = 'Failed'
        $entry.Error = $_.Exception.Message
        $auditEntries.Add([pscustomobject]$entry)
    }
    throw
} finally {
    $audit = [pscustomobject]@{
        CreatedAt = (Get-Date).ToString('o')
        ReadOnlyProposalSource = [bool]$report.ReadOnly
        WindowStart = $report.WindowStart
        WindowEnd = $report.WindowEnd
        PlannedCount = $approved.Count
        ArchiveOnlyCount = $archiveOnly.Count
        ReadLaterThenArchiveCount = $readLaterThenArchive.Count
        Entries = @($auditEntries)
    }
    [System.IO.File]::WriteAllText($AuditPath, ($audit | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
}

if (@($auditEntries | Where-Object { $_.Status -eq 'Applied' }).Count -ne $approved.Count) {
    if ($WhatIfPreference) {
        Write-Host ("WhatIf completed for {0} approved newsletter actions. Local audit: {1}" -f $approved.Count, $AuditPath) -ForegroundColor Yellow
        exit 0
    }
    throw 'The approved batch did not complete. Review the local audit before retrying.'
}

Write-Host ("Applied {0} approved newsletter actions. Local audit: {1}" -f $approved.Count, $AuditPath) -ForegroundColor Green
