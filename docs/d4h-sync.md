# D4H sync

D4H is the system of record. SAR Duty keeps a local copy so pages load without an API
round trip, and so it can compute things D4H can't (letter hours, group rules). This doc
covers how the copy is refreshed and where it drifts from D4H.

## When it runs

- Oban cron runs [ScheduleTeamRefreshesWorker](../lib/app/worker/schedule_team_refreshes_worker.ex)
  at 06:00 UTC daily (`config/config.exs`). It enqueues one
  [RefreshTeamDataWorker](../lib/app/worker/refresh_team_data_worker.ex) per team that has
  a `d4h_team_id`.
- The team dashboard's refresh button and the admin dashboard enqueue the same jobs.
- The `refresh` queue has a limit of 1, so one team refreshes at a time. A failed job
  retries after 15 minutes, then 30 (`max_attempts: 3`), before waiting for the next day.
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

- **Attendance, qualifications, awards, groups, and group memberships are deleted** when
  D4H stops returning them, at the end of each one's stage. A deleted qualification takes
  its awards with it, and a deleted group its memberships.
  [StaleRows](../lib/app/operation/refresh_d4h_data/stale_rows.ex) finds the rows, always
  within one team.
- **Members and activities are never deleted.** A member deleted in D4H keeps their
  contact details here. Attendance and tax credit letters point at them.
- **A member D4H stops listing is marked departed.** D4H's `GET /members` leaves deleted
  members out, so the members stage sets `left_at` to the refresh time on any active
  member it didn't see (#72). It skips this when D4H returns no members at all. If D4H
  lists the member again, the next refresh copies D4H's `endsAt` back.
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
misses per email and IP. A login lasts until the browser closes; only ticking "Remember
me on this computer for 60 days" (off by default) sets the 60-day cookie. A user reaches
a team when their email matches one of its managers in the local copy: a D4H Owner or
Editor who isn't retired and hasn't left
(`App.Model.Member.manager?/2`, and `App.Model.Team.get_managed_by/2` as a query). Losing
Owner or Editor in D4H loses access at the next refresh. Admins reach every team, but
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
- `/:subdomain/managers` shows the team who can log in, with the same list on `/admin`.
- **New teams sign themselves up** at `/signup` (`App.Operation.SignUpTeam`): a D4H
  personal access token becomes the team key, and the person signing up must be a current
  Owner or Editor on that team in D4H, at the email they give. The team goes live at once,
  its first refresh starts, every admin gets an email, and the signer gets a login code.

## Adapter notes

- The base URL is `https://<team.d4h_api_host>/v3/team/<d4h_team_id>`. The host is the
  team's D4H region; `D4H.regions/0` lists them.
- Every list endpoint goes through `reduce_pages` in the adapter, `page` from 0 with
  `size: 1000`. It stops when the rows reach D4H's `totalSize`, and raises `D4H.Error` on
  a non-200 response or a short fetch.
- Other calls read the body without checking the status. A bad key there surfaces as a
  `MatchError` that the worker turns into `D4H API error (status): …`. #33 covers them.
- `Parse.datetime/1` expects D4H timestamps in UTC and raises on any other offset.
