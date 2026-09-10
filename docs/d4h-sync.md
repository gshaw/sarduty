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
- The `refresh` queue has a limit of 1, so one team refreshes at a time. Jobs have
  `max_attempts: 1` — a failure waits for the next day.
- A successful run pings `HEALTHCHECKS_URL`. A failed one writes `Error: …` to
  `teams.d4h_refresh_result`, which the dashboard shows.

## Which key

[ResolveAccessKey](../lib/app/operation/refresh_d4h_data/resolve_access_key.ex) uses the
team's own key (`teams.d4h_access_key`, set in team settings). Without one, it borrows the
first team member's personal key. Both are `EncryptedString` columns. The fallback is
marked for removal once every team has a key.

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
topic. `TeamDashboardLive` matches stage names against its own `@refresh_stages` list, so
renaming a stage means changing both.

## Where the copy drifts

- **Only attendance is ever deleted.** Attendance rows D4H no longer returns are removed
  at the end of that stage. Members, activities, qualifications, awards, groups, and group
  memberships that are deleted in D4H **stay** in SAR Duty. This is why #18 sees deleted
  qualifications.
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
- Paged endpoints use `page` from 0 with `size: 1000`, and callers loop until an empty
  page. Members, qualifications, groups, and tags use `size: -1` for everything at once.
- Responses are read as `body["results"]` without checking the status. A bad key usually
  surfaces as a `MatchError` that the worker turns into `D4H API error (status): …`.
- `Parse.datetime/1` expects D4H timestamps in UTC and raises on any other offset.
