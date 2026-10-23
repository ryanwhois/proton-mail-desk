# Zero Inbox workflow

The Inbox is a temporary decision queue. It should contain only mail that still needs a decision—not a long-term filing system or task manager.

## Daily state labels

The current workflow uses exactly three labels:

| Label | Meaning | Next step |
| --- | --- | --- |
| `Action` | You need to do something. | Create or complete the task, then archive the message. |
| `Waiting` | Another person or service owes the next step. | Review the label periodically; archive the message after the outcome is settled. |
| `Read Later` | Worth reading, but not now. | Read during a deliberate reading block, then archive. |

Labels are a state, not a subject. Use folders only for durable reference categories such as invoices, healthcare, work material, or long-lived projects.

## Process every new message once

1. Delete or unsubscribe when it has no value.
2. Do a sub-two-minute task immediately, then archive.
3. Add `Action`, `Waiting`, or `Read Later` when applicable.
4. Archive, move to a reference folder, or trash the message once there is no further Inbox decision.

The Mail Desk's **Label** action adds one of the three workflow labels but does not move the message. That separation keeps a choice reversible and makes the next action explicit.

## Adoption plan

1. Use the three labels only for new mail for one to two weeks.
2. Start each recent-window session with `npm.cmd run inbox:triage`. It is a read-only header inventory that groups recent messages by sender and flags security, financial/official, work/calendar, and delivery/order metadata for individual review.
3. Process the most recent 7–14 days of the Inbox manually; do not begin with the historic backlog. Do not bulk-archive a sender group until it has been sampled and any review-flagged messages are excluded.
4. Review the old, empty workflow labels only after the new names are established. Do not alter `Axis` without a separate inventory and review because it is a large historic classification.
5. Process older mail in previewed batches by sender, subject, or age. Never bulk-move or bulk-label a set without reviewing a representative sample and its count first.
