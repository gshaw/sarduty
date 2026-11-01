# Change history

Every member and activity has a History tab, for team admins only (#174, step 3):
`/teams/:subdomain/members/:id/history` and `/teams/:subdomain/activities/:id/history`.
An activity's is a tab beside Members and Equipment, with the activity's page around it
([ActivityHistoryLive](../lib/web/live/activity_history_live.ex) keeps the team admin
access; [ActivityLive](../lib/web/live/activity_live.ex) draws it).
It answers "why did Jane drop out of the callout group?" with "her First Aid was removed
from D4H on Oct 3". It merges these sources, newest first
([ChangeHistory](../lib/app/view_data/change_history.ex)):

- **Changed by SAR Duty**: applied rows from [change sets](change-sets.md), with the source
  and the account that sent them.
- **Standing**, on a member's page only: away periods added, ended early, or deleted, and
  Not a person turned on or off, with the team admin who did it (#366). These are SAR
  Duty's own data, from `member_standing_changes`.
- **Seen in D4H**: `d4h_changes`, what the refresh saw change in D4H since the run
  before. D4H says neither when nor who, so the page shows the window between the 2 runs
  ("Oct 9, 10:00 to 10:10") and "Someone outside SAR Duty". D4H's API has a `createdBy` on some
  records but no `updatedBy` and no audit log (checked in its spec, 2026-10-07).

## What gets history

One rule (#651): history shows what changed in D4H, from change sets and what the
refresh saw, and changes to a member's standing. SAR Duty-only records that are cheap to
make again get none.

- **A deleted group keeps a snapshot.** Its delete row's `old_value` holds its members'
  names and its rules as words, and `ChangeHistory.describe_row/2` prints "Deleted MIT
  2026: 14 members; rules: In MIT Applicants, Not in LOA". A mistaken delete can be
  rebuilt by hand. No new table and no new source.
- **An activity's own SAR Duty fields ride on its change set row**, an exception to the
  rule: Enough at and Full at (#447) never go to D4H, yet History names who changed them
  and from what to what. `SaveActivity` puts them, and the hours choice, on the row's old
  and new values; the adapter sends neither, so a row with only them makes no request.
  `ChangeHistory.describe_row/3` writes a sentence per form box ("Enough at changed from
  8 to 10. Full at set to 14"), and a row with a key no box sends reads "Details changed
  in SAR Duty".
- **Group rule edits aren't logged.** The snapshot covers the delete that loses work.
- **A no-show's Remove is a plain delete**, with no entry (#650).
- **No undo, no trash, no delayed delete.** D4H can't restore what it deletes, so none of
  these could bring the record back. A delete that takes other things with it asks for a
  ticked box instead: the confirm dialog at `/styles/confirm-dialog`.

## How changes are recorded

The upsert stages in `lib/app/operation/refresh_d4h_data/` already compare each D4H row
with the local copy and write only what differs. They now pass the old and new record to
[RecordD4HChanges](../lib/app/operation/record_d4h_changes.ex) as they write, and the rows
they delete or mark as retired or deleted. The full refresh and the sync every 10 minutes wrap
their run in `RecordD4HChanges.recording/3`, which holds the team and the window in the
process dictionary, so the stages don't each carry it. Outside a run nothing is recorded.

- **Tracked fields only.** Members: name, position, status, D4H access, joined, left.
  Activities: title, start, end, published, tags, deleted in D4H. Attendance: status,
  times, duration. Qualification awards: start and expiry. Group memberships: added and
  removed. Anything else D4H changes, such as `updatedAt` or an activity's description, is
  noise.
- **Contact details** (email, phone, address) are logged as "Contact details changed",
  and emergency contacts as "Emergency contact changed" (#423), with the field names and
  never the values. A member's own save says the same, "… changed in SAR Duty". An
  emergency contact's first copy, from nil, is the baseline and records nothing.
- **The baseline.** A team's first full refresh copies the whole team and records nothing.
  Recording starts once `teams.d4h_refreshed_at` is set. Teams already on SAR Duty start
  from their current copy, so day 1 logs only real changes.
- **SAR Duty's own writes aren't logged twice.** Attendance written by a change set comes
  back on the next sync like anyone's change. A change to an attendance row that an
  applied row wrote in the last day, with the same status, is skipped. Group rules update
  the copy as they write, so their changes never reach the recorder. An edit of a team on
  SAR Duty Records ([records.md](records.md)) is skipped by the sync that copies it back:
  any change to that record seen since the edit applied.
- **Deleted qualifications and groups** take their awards and memberships with them, and
  those are recorded as removed. Each row keeps the qualification's or group's name in
  `label`, since the row it points at is gone.

## Retention and limits

- Attendance and award changes are kept for good. The rest go after 2 years, pruned each
  night by `PruneEventsWorker` (`D4HChange.prune/1`).
- Only what SAR Duty copies. A change undone within one sync window never shows.
- A change that moves neither a list's total nor its `updatedAt` waits for the nightly
  refresh, as in [d4h-sync.md](d4h-sync.md#where-the-copy-drifts), so its window is a day.
- A page lists the newest 200 entries.
