# Zero Inbox workflow

The Inbox is a temporary decision queue. It should contain only mail that still needs a decision—not a long-term filing system or task manager.

## Daily state labels

The current workflow uses exactly three labels:

| Label | Meaning | Next step |
| --- | --- | --- |
| `Action` | You need to do something. | Apply the label, then archive; the label is the follow-up queue. |
| `Waiting` | Another person or service owes the next step. | Apply the label, then archive; periodically review the label. |
| `Read Later` | Worth reading, but not now. | Apply the label, then archive; read it from the label queue. |

Labels are a state, not a subject. Use folders only for durable reference categories such as invoices, healthcare, work material, or long-lived projects.

## Process every new message once

1. Delete or unsubscribe when it has no value.
2. Do a sub-two-minute task immediately, then archive.
3. Add `Action`, `Waiting`, or `Read Later` when applicable, then archive so the state label—not Inbox—holds the deferred item.
4. Mark read only as part of a final outcome: normally archive, move to a reference folder, or trash once there is no further Inbox decision. Do not use “mark read” alone as a workflow state.

The Mail Desk's **Label** action adds one of the three workflow labels but does not move the message. That separation keeps a choice reversible and makes the next action explicit.

## Adoption plan

1. Use the three labels only for new mail for one to two weeks.
2. Start each recent-window session with `npm.cmd run inbox:triage`. It is a read-only header inventory that groups recent messages by sender and flags security, financial/official, work/calendar, and delivery/order metadata for individual review.
3. Process the most recent 7–14 days of the Inbox manually; do not begin with the historic backlog. Do not bulk-archive a sender group until it has been sampled and any review-flagged messages are excluded.
4. Review the old, empty workflow labels only after the new names are established. Do not alter `Axis` without a separate inventory and review because it is a large historic classification.
5. Process older mail in previewed batches by sender, subject, or age. Never bulk-move or bulk-label a set without reviewing a representative sample and its count first.

## Proposal-only policy

`npm.cmd run inbox:proposals` applies the agreed policy as a read-only recommendation engine. It has no apply mode: every result is a reviewable proposed action, and no message is changed by the command. `npm.cmd run inbox:worksheet` writes the current manual decisions, including header metadata, to a local editable Markdown file under `.local/reports/`.

The initial policy is deliberately narrow:

- Financial Times and Eater: the newest edition is proposed for `Read Later` **then archive**; older editions are proposed for archive. The report retains an occasional unsubscribe reminder.
- GitHub access/security mail remains manual. Build, deployment, and error notifications are shown as potential `Action` items; other non-security notifications need a message-level decision before a default is added.
- Revolut promotions are shown as potential `Read Later` items. Account, payment, and card messages remain unread and are individually reviewed before they are starred.
- Propstep, deliveries, bookings, receipts, invoices, health, government, legal, debt, and direct-person/work mail are never batch-handled by this policy. The report will surface specific examples so their folder and label rules can be agreed safely.

## Applying an approved batch

The current apply command is intentionally limited to the reviewed Financial Times and Eater newsletter rule. It rebuilds the live read-only proposal immediately before taking action and rejects any sender, rule, or action outside that scope.

```powershell
# Preview the exact current batch; makes no changes.
npm.cmd run inbox:apply-approved

# Apply only after a reviewed batch has explicit approval.
.\scripts\Invoke-ProtonMailApprovedBatch.ps1 -ConfirmApply
```

The command adds `Read Later` then archives each current edition, archives older editions, and saves a local audit under `.local/reports/`. It stops if any operation fails; inspect that audit before considering a retry.
