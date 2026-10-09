# Change sets

Every write SAR Duty makes to D4H is a change set (#174, step 1). A change set is a list
of D4H edits with what proposed them (`source`: the door, a group rule, or a pasted
attendance report), one row per D4H record, and D4H's answer for each row. They live in
`change_sets` and `change_set_rows`
([ChangeSet](../lib/app/model/change_set.ex),
[ChangeSetRow](../lib/app/model/change_set_row.ex)).

[ApplyChangeSet](../lib/app/operation/apply_change_set.ex) is the only module that calls
D4H's write functions, and
[a test](../test/app/operation/apply_change_set_test.exs) fails if anything else does. A
new kind of write is a new row action there, not a new call from a page or an operation.

- **Propose, then apply.** A caller builds the rows with `ChangeSet.propose!/2` and hands
  the set to `ApplyChangeSet.call/4`. The door, group rules, and import attendance
  propose and apply in one click, since each has its own review page first.
- **An AI agent's set waits** (#216). An agent connected through MCP proposes attendance
  changes for one activity
  ([ProposeAttendanceChanges](../lib/app/operation/propose_attendance_changes.ex)), as
  source `agent` with its own one-line `summary`. Nothing reaches D4H until a team admin
  opens it under "Proposed changes" (`/teams/:subdomain/proposed-changes`, also on the
  team home's "Needs attention"), clears the rows they don't want, and sends it
  ([ApplyProposedChangeSet](../lib/app/operation/apply_proposed_change_set.ex)). Cleared
  rows are recorded as skipped, "Not selected". A set can be discarded instead. An agent
  can never apply a set, and it can't propose group or award changes yet: group rules
  own their groups, and awards wait on #174's step 4.
- **An edit is a set of one row** (source `edit`): a team admin changing one record of
  a team on SAR Duty Records ([records.md](records.md)).
  [ApplyEdit](../lib/app/operation/apply_edit.ex) proposes and applies it in one step,
  then runs the sync so the next page shows the change. The row names only the fields
  that changed, with their old values. Edits don't read D4H first.
- **A member's own edit is a set of one row** (source `member`, #156): a member
  changing their address or emergency contacts from their page, applied at once. See
  [members.md](members.md).
- **D4H is read fresh before writing.** An attendance set reads the activity's rows and
  published flag. A row whose D4H status changed since it was proposed is skipped, not
  overwritten, and a create is skipped when D4H has a row for that member now, since D4H
  would count their hours twice. Group rows aren't checked; D4H treats a removed
  membership as gone already.
- **Each row records D4H's answer**: `applied` with the D4H record id (a create's new id),
  `failed` with D4H's error, or `skipped` with why. Writes don't retry. Applying the set
  again tries its proposed and failed rows once more.
- **`old_value` and `new_value`** hold what D4H had and what it gets, as JSON with string
  keys and times as ISO 8601 strings.
- **Local side effects stay with the caller.** The door records no-shows and group rules
  update `group_members` from the rows that applied. Group rules still log to
  `group_membership_changes`, which the group page shows.

Applied rows show on each member's and activity's history page, beside what the refresh
saw change in D4H: see [change-history.md](change-history.md).

Still to come from #174: review settings per source, Oban for big sets, and undo.
