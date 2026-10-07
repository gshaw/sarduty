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
  the set to `ApplyChangeSet.call/4`. The three callers today propose and apply in one
  click, since each has its own review page first.
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

Still to come from #174: review settings per source, Oban for big sets, undo, a history
page from the sync's differences, and agents proposing sets through MCP.
