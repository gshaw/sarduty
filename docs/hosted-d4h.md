# Hosted D4H

Some teams can't pay for D4H. For them SAR Duty keeps the records itself, behind an API
shaped like D4H's v3. Everything else in SAR Duty treats a hosted team as a D4H team:
the sync copies its records into `members`, `activities`, and the rest, change sets
write to it, and every page reads the copy. One code path serves both kinds of team.

Why an API rather than a second kind of team (2026-10-08): the sync, change sets,
`d4h_*_id` columns, and history stay as they are, editing screens are built once and
tested against the store, and a team that later buys D4H moves between two APIs of the
same shape. The cost is drift: code that passes against the store can fail against D4H,
so the store follows D4H's spec (`api.d4h.org/v3/docs/swagger.json`) and refuses what
D4H refuses. It lives in this app, not on Cloudflare, so hosted records stay in the
Canadian database the privacy page promises.

## How a hosted team is wired

- The store is the `hosted_*` tables, with schemas in
  [lib/app/hosted/](../lib/app/hosted) and the queries and writes in
  [App.Hosted](../lib/app/hosted.ex). These rows are the system of record. Their ids
  are the team's "D4H ids" in `d4h_*_id` columns.
- [App.Hosted.API](../lib/app/hosted/api.ex) serves the store in D4H's shape, and
  [App.Hosted.JSON](../lib/app/hosted/json.ex) renders it. Only the fields the D4H
  adapter reads are there.
- A hosted team's `d4h_api_host` is `hosted.sarduty.com` (`D4H.hosted_host/0`). For that
  host the adapter adds Req's `plug: App.Hosted.API`, so the request runs in-process and
  never leaves the app. Tests use the same path, so a test of a hosted team runs the real
  store rather than a stub.
- The team's D4H key is a hosted key (`sdh_…`), encrypted in `teams.d4h_access_key` like
  any D4H key. The store keeps only its SHA-256. `whoami` names the key's member
  "SAR Duty", id 0, so the key never counts as a manager.
- The API is also served at `/d4h/v3/…` with the same bearer key, for anything else that
  speaks D4H. The key decides the team, and a path naming another team is a 403. No page
  shows the key; read it with `bin/sarduty rpc` as `Team.get_by(subdomain: …).d4h_access_key`.
- Hosted team ids start at 2,000,000,000, so a hosted `d4h_team_id` never matches a real
  D4H team's, which are small.

## Creating a hosted team

An admin creates one at `/admin/teams/new` (`App.Operation.CreateHostedTeam`): the
team's name, short name (its subdomain), time zone, and first manager. The manager is an
Owner in the store, so they log in with that email as soon as the page saves. The first
refresh runs right there rather than on the queue. A box adds made-up members,
activities, attendance, qualifications, and groups (`App.Operation.SeedHostedTeam`) for a
team trying SAR Duty out.

A hosted team's pages hide what only D4H has: the "Open D4H" links and the D4H key in
team settings. The nightly refresh and the sync every 10 minutes run for it as for any
team.

## Editing records

A hosted team's admins change its records in SAR Duty. Each change is a change set of
one row with source `edit`, applied at once by
[ApplyEdit](../lib/app/operation/apply_edit.ex), which then syncs so the page that
follows shows it. So every edit is in the member's or activity's history, and the store
is only ever written through its API. The pages are for hosted teams only; a D4H team
gets a 404 and edits in D4H.

- **Members**: add, change details, make a team admin (`permission` 0) or not (2), and
  mark as left or rejoined (D4H's retire). `/members/new`, `/members/:id/edit`.
- **Activities**: add any kind, change its title, times, place, tracking number,
  description, and published flag, and delete it. The tax credit hours choice sets the
  `Primary Hours` or `Secondary Hours` tag, which every hosted team gets when it's
  created. The place is one line, kept as the address's street. A delete also marks the
  copy at once, since the sync never marks the last activity of a kind.
  `/activities/new`, `/activities/:id/edit`.
- **Attendance** needs nothing new: the door, import attendance, and an AI agent's
  proposals write to the store through change sets as they write to D4H.

## What it serves

Every endpoint the [D4H adapter](../lib/app/adapter/d4h.ex) calls, with D4H's paging
(`page`, `size` up to 1000, `totalSize`), `sort=updatedAt&order=desc`, and the filters
the sync uses (`updated_after`, `activity_id`, `starts_after`, `starts_before`,
`member_id`, `group_id`). Writes take D4H's camelCase bodies and answer with the row, or
a 400 whose `title` says what's wrong.

Beyond D4H's own API, so a team can run from SAR Duty alone:

- `POST /members`. D4H adds members only in its web app.
- `permission` on a member (`OWNER`, `EDITOR`, `MEMBER`, `MEMBER_PLUS`, `NO_ACCESS`, or
  0–4). It decides who manages the team, as it does for D4H teams.
- `DELETE` on events, exercises, and incidents, which marks them deleted as D4H does.
- `PATCH` and `DELETE` on qualification awards, and `DELETE` on qualifications.

Not served: photos and documents (the lists come back empty, member images 404),
roles, custom fields, and animals.

## Hazards

- **Change times are what the sync compares.** Every write bumps the row's `updated_at`,
  and `fetch_list_head` keeps them to the microsecond, since in-process writes land within
  the same second.
- **Members are never deleted**, only retired, as in D4H: attendance and letters point at
  them. A tag on any activity can't be deleted either: letters count hours by its title.
- **Activity references are numbered** when a write gives none: five digits, after the
  team's count of activities.
