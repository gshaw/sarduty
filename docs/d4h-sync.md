# D4H sync

D4H is the system of record. SAR Duty keeps a local copy so pages load without an API
round trip, and so it can compute things D4H can't (letter hours, group rules). This doc
covers how the copy is refreshed and where it drifts from D4H.

## When it runs

Two runs keep the copy fresh: a sync of what changed, every 10 minutes, and a full
refresh once a night as the safety net (#163).

### The sync every 10 minutes

- Oban cron runs [ScheduleTeamSyncsWorker](../lib/app/worker/schedule_team_syncs_worker.ex)
  every 10 minutes. It enqueues one
  [SyncTeamChangesWorker](../lib/app/worker/sync_team_changes_worker.ex) per team with a
  key, on the `sync` queue, so it never waits behind another team's full refresh. Oban's
  `unique` keeps it to one job per team, and a team whose full refresh is running is
  skipped.
- Opening the team dashboard queues one too, when the last sync is over 2 minutes old.
- [SyncD4HChanges](../lib/app/operation/sync_d4h_changes.ex) asks each of the 10 lists for
  one row sorted by `updatedAt`, 4 at a time. That gives each list's total and newest
  change. If none moved since the last look (`teams.d4h_sync_state`), it stops: 10 small
  requests.
- A small list that moved (members, qualifications, awards, groups, memberships) is
  fetched whole through the full refresh's own stage, along with the lists that point at
  it, so rows skipped for an unknown parent come in. Their stale-row deletes and the
  member departure rule keep working.
- Activities that moved are fetched with `updated_after`, and `deleted=true&updated_after`
  marks new deletes (#160). A tag change refetches every activity, since activities store
  tag titles.
- Attendance has no `updated_after`, so it pages by `updatedAt` descending until rows are
  older than the cursor. Then each activity touched by either step has its attendance
  fetched whole, and local rows D4H didn't return are deleted.
- When the attendance totals still differ, counts by year and then by month find a
  window, and that month is fetched again with its stale rows deleted. This finds deletes
  on activities nothing else touched. At most one month per sync, and it's logged: rows
  D4H has but this copy skips keep the counts apart.
- The cursor is the newest `updatedAt` D4H showed last time, less 5 minutes, so the
  server's clock never matters.
- Nothing changed means no broadcast. A change broadcasts on `team_refresh` and queues
  pass updates. Syncs never write `d4h_refresh_result`; they set `teams.d4h_synced_at`,
  and the dashboards say "Updated from D4H 4 min ago".
- A failed sync isn't retried, since the next is 10 minutes away. Honeybadger hears about
  it once, after an hour of failures. A missing or rejected key is left for the nightly
  refresh to report. Each sync pings `HEALTHCHECKS_SYNC_URL` when it's set: give it its
  own check with a 10-minute period.

### The full refresh every night

- Oban cron runs [ScheduleTeamRefreshesWorker](../lib/app/worker/schedule_team_refreshes_worker.ex)
  at 06:00 UTC daily (`config/config.exs`). It enqueues one
  [RefreshTeamDataWorker](../lib/app/worker/refresh_team_data_worker.ex) per team that has
  a `d4h_team_id`.
- The team dashboard's refresh button and the admin dashboard enqueue the same jobs.
- The `refresh` queue has a limit of 1, so one team refreshes at a time. A failed job
  retries after 15 minutes, then 30 (`max_attempts: 3`), before waiting for the next day.
- It records the list heads it saw before its first stage, so the next sync picks up
  whatever changed while it ran. At the end it logs how many rows it wrote that the
  syncs missed. If that stays at zero for a month, run it weekly.
- A successful run pings `HEALTHCHECKS_URL`. A failed one writes `Error: …` to
  `teams.d4h_refresh_result`, which both dashboards show. When the last attempt fails, the
  error goes to Honeybadger.
- A missing key, or one D4H rejects with 401 or 403, is not an app error. The job writes
  `Error: No D4H key…` or `Error: D4H rejected the team key (401)…` and cancels, so it is
  neither retried nor sent to Honeybadger. It tries again the next night.

## Which key

Every D4H request uses the team's key (`teams.d4h_access_key`, an `EncryptedString` set
in team settings). Users have no D4H keys.

Each team should create the key from a D4H member named "SAR Duty" rather than a
person, so D4H history shows SAR Duty for changes made here and the key outlives the
people on the team. `teams.d4h_access_key_owner` holds the key's D4H member name, from
`whoami` when the key is saved and at the start of every refresh. Team settings and
`/admin` flag a key whose owner isn't a SAR Duty account. D4H doesn't say when a token
expires.

Team settings never sends the saved key back to the page. A new key goes through
[UpdateTeamSettings](../lib/app/operation/update_team_settings.ex), which asks D4H `whoami`
and saves it only if the key's member is on this team. A blank field keeps the saved key.

## The stages

[RefreshD4HData](../lib/app/operation/refresh_d4h_data.ex) runs these in order, in one
process, **without a transaction** — a failure halfway leaves the earlier stages written:

1. Team logo, saved to `$TEAM_LOGO_PATH/<subdomain>.png` (disk, not the database).
2. Members.
3. Tags (kept in memory to turn activity tag references into titles).
4. Exercises, events, incidents → `activities`.
5. Attendance.
6. Qualifications, then qualification awards.
7. Groups, then group memberships.

Order matters: attendance needs members and activities, awards need qualifications,
memberships need groups. A row whose parent is unknown locally is skipped.

Each stage does `get_by` then `update!` or `insert!` on the D4H id, rather than an
`on_conflict` upsert, because the real upsert does not set `updated_at`
([upsert_members.ex](../lib/app/operation/refresh_d4h_data/upsert_members.ex)).

Progress goes through [Progress](../lib/app/operation/refresh_d4h_data/progress.ex): each
update writes `teams.d4h_refresh_result` and broadcasts on the `"team_refresh"` PubSub
topic. `Team.refresh_state/1` reads the column for both dashboards: `OK`, anything
starting `Error:` is a failure, and any other text is a stage in progress.

## Where the copy drifts

- **Up to 10 minutes behind** for anything D4H marks with a new `updatedAt`, and for
  adds and deletes, which move a list's total. A change that moves neither waits for
  the nightly refresh. A member's status change and permission change (Owner to Editor
  and back, in D4H's web app) both move the member's `updatedAt`, so losing manager
  access reaches SAR Duty within 10 minutes (tested 2026-10-06).

- **Attendance, qualifications, awards, groups, and group memberships are deleted** when
  D4H stops returning them, at the end of each one's stage. A deleted qualification takes
  its awards with it, and a deleted group its memberships.
  [StaleRows](../lib/app/operation/refresh_d4h_data/stale_rows.ex) finds the rows, always
  within one team.
- **Members and activities are never deleted.** A member deleted in D4H keeps their
  contact details here. Attendance and tax credit letters point at them, and attendance
  links, scans, and no-shows point at activities.
- **A member D4H stops listing is marked departed.** D4H's `GET /members` leaves deleted
  members out, so the members stage sets `left_at` to the refresh time on any active
  member it didn't see (#72). It skips this when D4H returns no members at all. If D4H
  lists the member again, the next refresh copies D4H's `endsAt` back.
- **An activity D4H stops listing is marked deleted** (#160). D4H leaves deleted
  activities out of `GET /events`, `/exercises`, and `/incidents`, and a fetch for one
  returns 404. At the end of each kind's stage, `UpsertActivities.plan_deleted/2` picks
  this team's activities of that kind D4H didn't list, and the stage sets
  `activities.deleted_at` to the refresh time and closes their open attendance links. It
  skips a kind D4H returns none of. If D4H lists one again, the mark clears.
- Deleted activities are left out of the activity list, its years, the dashboard count,
  and letter hours. D4H already returns no attendance for them, so the attendance stage
  deletes theirs. Their page says "Deleted in D4H" and offers no actions. Take attendance,
  import attendance, and the mileage report send you back to it, an attendance link on one
  takes no scans, and `SendAttendanceToD4H` refuses it.
- Group rule clauses are never deleted by the sync. A clause for a deleted group is left
  unused; a clause naming a deleted qualification shows a warning on the group page.
- **A short fetch fails the refresh.** Every D4H list response has a `totalSize`. The
  adapter pages until the rows add up to it, and raises `D4H.Error` if a page comes back
  empty first, so the delete never runs on a partial list. Nothing local points at the
  deleted rows, so a row deleted by mistake loses nothing and the next refresh restores it.
  One gap remains: D4H pages by offset, so a row deleted in D4H mid-refresh shifts the
  next one out of view, and that row is gone until the next refresh.
- The team's name and time zone are copied when the team is created and when an admin
  clicks refresh in team settings, not on the daily sync.
- Activity tags are stored as titles. Letter hours depend on the exact titles
  `Primary Hours` and `Secondary Hours` (`App.Model.Activity`).

## Pages that skip the copy

Some pages call D4H live instead of reading the database: activity attendance (which
writes, via `PATCH /attendance/:id`), the mileage report, team settings refresh, and
member photos. They use the team's key too.

The sync also stores each member's D4H access level (`d4h_permission`) and status. That
decides who can log in: see [Who can log in](#who-can-log-in).

Group rule changes are the other write. The review page sends them with the team's key
and updates `group_members` right away rather
than waiting for the next refresh. See [group-rules.md](group-rules.md).

## Who can log in

Login is by emailed code only (#142, replacing the link from #57). A code is six digits,
works once for 15 minutes, and dies after 5 wrong tries; `Web.LoginLimit` caps sends and
misses per email and IP. 20 wrong codes in a day block an email or number, and its owner
gets an email saying so, but a browser that has logged in to it before (a signed
`_sarduty_known_browser` cookie) is never blocked by them, so nobody can lock a person out
of their own browsers (#176). A login lasts until the browser closes; only ticking "Remember
me on this computer for 60 days" (off by default) sets the 60-day cookie. A user reaches
a team when their email matches one of its managers in the local copy: a D4H Owner or
Editor who isn't retired and hasn't left
(`App.Model.Member.manager?/2`, and `App.Model.Team.get_managed_by/2` as a query). Losing
Owner or Editor in D4H loses access at the next sync, within 10 minutes. Admins reach every team, but
an admin logs in only while D4H lists their email as a current member of some team, any
permission (`App.Model.Member.current_email?/2`, #141). If D4H drops both admins, the way
back in is `bin/sarduty eval` ([deployment.md](deployment.md)).

- **The team key's account** is left out when it's a "SAR Duty" account, since it isn't a
  person. A team key from a person's own account leaves them in.
- **Login grants** let an email into one team that D4H doesn't list as a manager there: a
  shared role address, or a team whose key fails. An admin adds one through
  `bin/sarduty rpc`:
  `App.Model.TeamLoginGrant.grant!(subdomain, email, reason)`, and removes it with
  `revoke!(subdomain, email)`. `/admin` and the team's managers page list them.
- **The link** is 128 random bits, stored only as a hash, valid for 15 minutes and once.
  A request within a minute of the last one sends nothing, and `Web.LoginLimit` caps
  requests per email and per IP. Opened in the browser that asked for it, the link logs
  in on its own; anywhere else it waits for a button, so mail scanners can't use it up.
- **Landing**: the page that asked for a login, else the team the user last opened
  (`users.last_team_id`), else their first. An admin with no team lands on `/admin`.
- `/teams/:subdomain/settings/managers` shows the team who can log in, with the same list on `/admin`.
- **New teams sign themselves up** at `/signup` (`App.Operation.SignUpTeam`): a D4H
  personal access token becomes the team key, and the person signing up must be a current
  Owner or Editor on that team in D4H, at the email they give. The team goes live at once,
  its first refresh starts, every admin gets an email, and the signer gets a login code.

## Adapter notes

- The base URL is `https://<team.d4h_api_host>/v3/team/<d4h_team_id>`. The host is the
  team's D4H region; `D4H.regions/0` lists them.
- Every list endpoint goes through `reduce_pages` in the adapter, `size: 1000`. Page 0
  gives D4H's `totalSize`; the rest are fetched 4 at a time and handed on in order. It
  raises `D4H.Error` on a non-200 response or when the rows fall short of the total. A
  full attendance list took 35 s one page at a time and 15 s four at a time.
- Other calls read the body without checking the status. A bad key there surfaces as a
  `MatchError` that the worker turns into `D4H API error (status): …`. #33 covers them.
- `Parse.datetime/1` expects D4H timestamps in UTC and raises on any other offset.
