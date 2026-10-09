# Change history

Every member and activity has a history page (#174, step 3):
`/teams/:subdomain/members/:id/history` and `/teams/:subdomain/activities/:id/history`.
It answers "why did Jane drop out of the callout group?" with "her First Aid was removed
from D4H on Oct 3". It merges two sources, newest first
([ChangeHistory](../lib/app/view_data/change_history.ex)):

- **Changed by SAR Duty**: applied rows from [change sets](change-sets.md), with the source
  and the account that sent them.
- **Seen in D4H**: `d4h_changes`, what the refresh saw change in D4H since the run
  before. D4H says neither when nor who, so the page shows the window between the 2 runs
  ("Oct 9, 10:00 to 10:10") and "Someone in D4H". D4H's API has a `createdBy` on some
  records but no `updatedBy` and no audit log (checked in its spec, 2026-10-07).

## How changes are recorded

The upsert stages in `lib/app/operation/refresh_d4h_data/` already compare each D4H row
with the local copy and write only what differs. They now pass the old and new record to
[RecordD4HChanges](../lib/app/operation/record_d4h_changes.ex) as they write, and the rows
they delete or mark as left or deleted. The full refresh and the sync every 10 minutes wrap
their run in `RecordD4HChanges.recording/3`, which holds the team and the window in the
process dictionary, so the stages don't each carry it. Outside a run nothing is recorded.

- **Tracked fields only.** Members: name, position, status, D4H access, joined, left.
  Activities: title, start, end, published, tags, deleted in D4H. Attendance: status,
  times, duration. Qualification awards: start and expiry. Group memberships: added and
  removed. Anything else D4H changes, such as `updatedAt` or an activity's description, is
  noise.
- **Contact details** (email, phone, address) are logged as "Contact details changed",
  with the field names and never the values.
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
