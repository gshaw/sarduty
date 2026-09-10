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
  `Error: No D4H key…` or `Error: D4H rejected …'s personal key (401)…` and cancels, so it
  is neither retried nor sent to Honeybadger. It tries again the next night.

## Which key

[ResolveAccessKey](../lib/app/operation/refresh_d4h_data/resolve_access_key.ex) uses the
team's own key (`teams.d4h_access_key`, set in team settings). Without one, it borrows the
personal key of the earliest member (lowest user id) who has one. Both are
`EncryptedString` columns. `/admin` marks the borrowed key with a "Refresh key" badge.
Most teams still rely on the fallback; #41 tracks moving them to their own key so it can
be deleted.

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

- **Only attendance is ever deleted.** Attendance rows D4H no longer returns are removed
  at the end of that stage. Members, activities, qualifications, awards, groups, and group
  memberships that are deleted in D4H **stay** in SAR Duty. This is why #18 sees deleted
  qualifications.
- **A short fetch fails the refresh.** Every D4H list response has a `totalSize`. The
  adapter pages until the rows add up to it, and raises `D4H.Error` if a page comes back
  empty first, so the delete never runs on a partial list. Nothing local points at
  attendance, so a row deleted by mistake loses nothing and the next refresh restores it.
  One gap remains: D4H pages by offset, so a row deleted in D4H mid-refresh shifts the
  next one out of view, and that row is gone until the next refresh.
- The team's name and time zone are copied when the team is created and when an admin
  clicks refresh in team settings, not on the daily sync.
- Activity tags are stored as titles. Letter hours depend on the exact titles
  `Primary Hours` and `Secondary Hours` (`App.Model.Activity`).

## Pages that skip the copy

Some pages call D4H live instead of reading the database: activity attendance (which is
also the one page that writes, via `PATCH /attendance/:id`), the mileage report, team
settings refresh, the access key check, and member photos. They use the signed-in user's
key, not the team's.

## Adapter notes

- The base URL is `https://<team.d4h_api_host>/v3/team/<d4h_team_id>`. The host is the
  team's D4H region; `D4H.regions/0` lists them.
- Every list endpoint goes through `reduce_pages` in the adapter, `page` from 0 with
  `size: 1000`. It stops when the rows reach D4H's `totalSize`, and raises `D4H.Error` on
  a non-200 response or a short fetch.
- Other calls read the body without checking the status. A bad key there surfaces as a
  `MatchError` that the worker turns into `D4H API error (status): …`. #33 covers them.
- `Parse.datetime/1` expects D4H timestamps in UTC and raises on any other offset.
