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

# Read-only Zero Inbox triage for the recent Inbox window
npm.cmd run inbox:triage
.\scripts\Get-ProtonInboxTriage.ps1 -Days 14

# Apply the approved policy in proposal mode only (makes no mailbox changes)
npm.cmd run inbox:proposals

# Generate a local, editable decision worksheet containing current message headers
npm.cmd run inbox:worksheet

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

`Get-ProtonInboxTriage.ps1` is deliberately read-only. It pages through enough Inbox headers to cover its date window, groups them by sender, and highlights messages whose metadata indicates security/account, official/financial, work/calendar, or delivery/order review. Use it to form a reviewed batch; it never archives, labels, moves, trashes, marks read, or opens message content.

`Get-ProtonMailActionProposals.ps1` evaluates the explicit policy in `config/mail-policy.psd1` against those same read-only headers. It proposes, but never applies, state labels and archive actions. `Action`, `Waiting`, and `Read Later` recommendations mean label **then archive**, preserving Inbox as the unprocessed queue. The initial policy covers Financial Times and Eater edition retention, plus conservative manual handling for GitHub, Revolut, financial/official mail, health/legal/debt messages, delivery/booking, invoices, and mail from people. Messages without a clearly approved rule remain out of the proposal list.

`New-ProtonMailDecisionWorksheet.ps1` creates an editable Markdown worksheet beneath `.local/reports/`. It contains current message-header metadata, suggested/default disposition codes, and a blank response column. The generated file is Git-ignored and includes no message bodies; it does not change mail.

## MCP server

Run the local MCP server with:

```powershell
npm.cmd run mcp
```

Point a supported MCP desktop client at the command above. The MCP process inherits the same encrypted local profile and full-access policy. Do not expose this MCP server on a network or public endpoint.

## Mail Desk: an interactive daily workflow

For a more approachable view than raw command output, launch the local terminal desk:

```powershell
npm.cmd run desk
```

It starts with a compact, numbered Inbox list and offers guided Inbox refresh, live search, message reading, workflow labels, archive, trash, mark-read, and compose actions. **Label** offers the Zero Inbox states `Action`, `Waiting`, and `Read Later` and always asks for confirmation. Reading and searching do not change any message. Archive and Trash ask for confirmation; sending asks for confirmation and uses the same irreversible-action safeguards as the command-line wrapper.

See [the Zero Inbox workflow](docs/zero-inbox.md) for the daily processing rule and the staged migration plan.

For one-click use, double-click `Launch Proton Mail Desk.cmd` in the repository root. To create a Desktop shortcut that you can pin, run this once:

```powershell
.\scripts\Install-ProtonMailDeskShortcut.ps1
```

Then right-click **Proton Mail Desk** on your Desktop and choose **Pin to taskbar**.

## Maintenance

```powershell
npm.cmd run check:powershell
npm.cmd run doctor
```

The project deliberately has no automatic sends, deletes, or background mailbox scan. Use explicit commands (including `sync` when you want to refresh the local index) and keep Proton Bridge signed in locally.
