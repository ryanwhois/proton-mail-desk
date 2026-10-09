# Proton automation

Reusable Windows automation for a locally running Proton Mail Bridge. It packages the community-maintained [Proton Mail Bridge Client](https://github.com/googlarz/proton-mail-bridge-client) locally, including its CLI and MCP server, and adds a PowerShell setup and safety layer.

## What it does

- Saves Bridge credentials once in an encrypted, per-user local profile.
- Confirms that Bridge is answering on local IMAP (`1143`) and SMTP (`1025`) before running a command.
- Lists, searches, reads, archives, moves, labels, drafts, and sends mail through the pinned upstream client.
- Starts a full MCP server for compatible desktop clients.
- Keeps credential material, message caches, and mail content out of Git.

## Setup

Prerequisites: Windows PowerShell 7+, Node.js 22+, Proton Mail Bridge signed in and running.

```powershell
Set-Location 'D:\Repos\60 Business Systems and Integrations\proton-automation'
npm.cmd ci
pwsh -NoLogo -NoProfile -File .\scripts\Initialize-ProtonBridgeProfile.ps1
```

Enter the mailbox username and the password displayed by Proton Mail Bridge. Do **not** enter your Proton account password. The setup writes `.local/bridge-profile.clixml`, encrypted for your Windows user; this file and the local mail index are ignored by Git.

Pass `-ReadOnly` at setup time if a read-only profile is needed. To change the policy or credentials later, add `-Replace`.

## Everyday commands

```powershell
# Recent Inbox messages
.\scripts\Get-ProtonMail.ps1 -Limit 25

# Inspect health and live connectivity
.\scripts\Invoke-ProtonMail.ps1 doctor --json
.\scripts\Invoke-ProtonMail.ps1 connection-status --json

# Search live mail
.\scripts\Invoke-ProtonMail.ps1 search --live --from example.com --limit 10

# Reversible mailbox actions
.\scripts\Invoke-ProtonMail.ps1 archive 'INBOX::12345'
.\scripts\Invoke-ProtonMail.ps1 move 'INBOX::12345' 'Folders/Receipts'

# Send or permanently delete only after reviewing arguments
.\scripts\Invoke-ProtonMail.ps1 -ConfirmDestructive send --to recipient@example.com --subject 'Subject' --body 'Message'
```

`trash`, `archive`, `move`, labels, and folders are ordinary mailbox changes. Sending and permanent deletion need `-ConfirmDestructive`; the wrapper forwards that confirmation to the upstream CLI's dedicated commands. Generic `tool` calls still need their own `confirmed:true` in their JSON arguments, because those arguments are passed through untouched.

## MCP server

Run the local MCP server with:

```powershell
npm.cmd run mcp
```

Point a supported MCP desktop client at the command above. The MCP process inherits the same encrypted local profile and full-access policy. Do not expose this MCP server on a network or public endpoint.

## Maintenance

```powershell
npm.cmd run check:powershell
npm.cmd run doctor
```

The project deliberately has no automatic sends, deletes, or background mailbox scan. Use explicit commands (including `sync` when you want to refresh the local index) and keep Proton Bridge signed in locally.
