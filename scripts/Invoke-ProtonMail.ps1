#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$ConfirmDestructive,
    [Parameter(ValueFromRemainingArguments = $true, Mandatory = $true)]
    [string[]]$ClientArguments
)

Import-Module (Join-Path $PSScriptRoot 'ProtonAutomation.psm1') -Force
$command = $ClientArguments[0].ToLowerInvariant()
$destructive = @('send', 'reply', 'forward', 'delete', 'empty-folder', 'unsubscribe-sender', 'test-email', 'draft-send', 'reply-to-email', 'reply-all-email', 'forward-email', 'delete-email', 'delete-thread', 'delete-label', 'tool')
if ($command -in $destructive -and -not $ConfirmDestructive) {
    throw "'$command' can make an irreversible change. Review the exact arguments, then re-run with -ConfirmDestructive."
}
Invoke-ProtonClient -Arguments $ClientArguments -RequireWriteAccess:($command -notin @('status', 'doctor', 'connection-status', 'runtime-status', 'folders', 'labels', 'threads', 'digest', 'followups', 'emails', 'attachments', 'search', 'read', 'thread', 'thread-brief', 'actionable', 'document-threads', 'meeting-context', 'stats', 'analytics', 'folder-stats', 'contacts', 'volume-trends', 'drafts', 'remote-drafts', 'get-logs', 'list-scheduled-sends', 'unsubscribe-info', 'get-email-by-id', 'get-emails-by-ids', 'search-emails', 'get-folders', 'get-connection-status', 'get-runtime-status', 'get-index-status', 'search-indexed-emails', 'get-labels', 'get-threads', 'get-inbox-digest', 'get-follow-up-candidates', 'list-attachments', 'get-attachment-content', 'get-attachment-text', 'get-audit-logs'))
