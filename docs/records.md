# SAR Duty Records

Some teams do not use D4H. Their records live in SAR Duty Records, a separate app at
<https://records.sarduty.com> (private repo `gshaw/sarduty-records`). Records serves
D4H's v3 API shape at `https://records.sarduty.com/v3/team/<id>/…`, so SAR Duty treats
it as one more place a team's records live. The refresh, the sync, change sets, and
every page work the same for both.

Why a separate app rather than a store inside SAR Duty (2026-10-08): SAR Duty keeps one
job, copying a team's records and building on them, and Records can grow its own logins
and approval without touching SAR Duty. The old in-app store (#252–#257) was closed for
this.

## How a team connects

1. A team admin signs the team up in Records, and a Records admin approves it.
2. On the team's API keys page in Records, they create a key, such as "SAR Duty".
3. At SAR Duty's sign-up, they choose **SAR Duty Records (experimental)** as the D4H
   region, and paste the key. The page leads with D4H, since almost every team has it,
   and mentions Records in one line.

Sign-up then runs as for a D4H team: `whoami`, the team, and its members come from
Records, and the person signing up must be an Owner or Editor there. The team's
`d4h_api_host` is Records' host, and its key is stored encrypted in `d4h_access_key`
like a D4H key. Existing D4H teams need no change.

## The service check

- `D4H.services/0` is the approved list: each D4H region, then SAR Duty Records. Sign-up
  validates against it, and SAR Duty never calls a host off it. There is no free URL.
- `D4H.service/1` says `:d4h` or `:records` for a team or a host, and `D4H.records?/1`
  is the short form. `D4H.service_name/1` and `D4H.key_name/1` give the words people
  read: "SAR Duty Records" and "Records access key".
- A Records team sees no "Open D4H" links. Text names the service only where the reader
  must go there, such as the team home's refresh line and team settings, and takes the name
  from the team: `@service`, set for every team page in `on_mount(:ensure_team_access)`.
  Everywhere else the words are true on both services ([writing.md](writing.md), rule 16).
- `D4H.records_host/0` is `records.sarduty.com`. In dev, `RECORDS_HOST` points it at a
  local copy.

## Editing records

D4H teams change most of their records in D4H. A Records team has nowhere else to do
it, so SAR Duty shows editing screens for Records teams; a D4H team gets a 404 and no
buttons. Two exceptions: every team adds, renames, and deletes groups and changes who is
in them ([group-rules.md](group-rules.md#groups-kept-by-hand-546)), and a D4H team adds
and changes activities (#585). Each change is a change set of one row, source `:edit`,
applied at once by [App.Operation.ApplyEdit](../lib/app/operation/apply_edit.ex) through
`ApplyChangeSet`, then the sync copies it back, except a group's, whose copy is written
from the answer. The row names only the fields that changed, with their old values, so it
shows in the record's history. ApplyEdit refuses a D4H team every row but a group's and
an activity's create and update.

Records refuses a bad write with a 400 whose `title` says what is wrong; the page shows
that title.

- **Members**: add, change details, team admin or not, mark as retired or rejoined.
  `POST /members` and `permission` are Records' own; D4H adds members and sets access
  only in its web app. Leaving is D4H's `PATCH /members/<id>/retire`. The last team
  admin cannot stop being one or leave, and saving a retired member's details keeps
  them retired.
- **Photos**: set or remove on the member's Change details page. `PUT` takes the image
  itself (JPEG, PNG, or WebP, under 10 MB), and Records shrinks it and strips its
  metadata. The change set row records only the size: the image passes through
  `ApplyChangeSet`'s `photo:` option and is never kept in SAR Duty. Reading is D4H's
  `GET /members/<id>/image`, as for any team, so ID cards and pages need nothing new.
  After a change, the member's Apple Wallet pass is nudged to fetch the new photo.
- **Activities**: add, change, delete. `DELETE /<kind>s/<id>` is Records' own; it marks
  the activity deleted as D4H does, and SAR Duty marks its copy at once. The tax credit
  hours choice sets the team's primary or secondary hours tag and keeps any others. A
  new activity keeps its id even if its tags or published flag fail, so a retry never
  makes a second one. Times are on the team's clock, to the minute.
- **Activities on a D4H team** (#585): add and change, never delete, since D4H's API has
  no delete; the form sends the team admin to D4H for it. A new one has `fullTeam` and
  `shared` false, as a chore event does, so D4H adds no one's attendance; Add members
  follows. The description is HTML in D4H and in Records. The form edits it in Trix
  with bold, italics, links, and lists, the way chore events are written (#599).
  [Service.DescriptionHTML](../lib/service/description_html.ex) drops everything else,
  such as pasted colours and fonts, and the form sends one only when it changed. A
  description with things the editor can't hold, such as a table, a picture, or a rule,
  is shown read only, so SAR Duty never flattens it. `reference` is D4H's to give out, so the form
  leaves it alone. The place goes in `address.street` with the other parts empty, since
  SAR Duty shows them joined; D4H answers 400 to a null part (tried on South Fraser,
  2026-10-25).

- **Qualifications and groups**: add, rename, delete. A qualification's awards change on
  the member's Qualifications tab, and groups on every team as for a D4H team. `DELETE` on
  qualifications and awards is Records' own; groups and group members use D4H's own
  endpoints. Deleting a qualification takes its awards with it, and a group its members.

- **Equipment items**: add, change, move, delete (#271, [equipment.md](equipment.md)).
  `POST`, `PATCH`, and `DELETE` on `/equipment` are D4H's, but `type` and changing
  anything beyond status and barcode are Records' own. A new place is D4H's
  `POST /equipment-locations`.

- **Whiteboard notes** (#515): Records serves D4H's `/whiteboard` in its shape, so the
  Dashboard card and the Whiteboard page work as for a D4H team. It is always on, and
  the Whiteboard page's Archived list is the only place a Records team sees old notes.

Records follows D4H's rules where they make sense, not where D4H's API lacks a write
such as delete (Gerry, 2026-10-25). Both answer 409 here, and the form says so first:

- **A published activity is locked.** Only its published flag changes; its details, tags,
  and attendance do not. The form greys out every field but Published.
- **Only an activity that has happened is published.** D4H answers "Activity cannot be
  marked ready for approval or published" before its finish (Andrew, 2026-10-25), so the
  form refuses Published until then.

Every Records-only write: `POST /members`, `permission` on a member, `PUT` and `DELETE`
on `/members/<id>/image`, `DELETE` on
`/events`, `/exercises`, and `/incidents`, `DELETE /member-qualifications/<id>`,
`DELETE /member-qualification-awards/<id>`, and `type` and every field but status and
barcode on `/equipment`. The guard test in
`test/app/operation/apply_change_set_test.exs` lists every write function, so only
`ApplyChangeSet` calls them.

## Where the code is

- [App.Adapter.D4H](../lib/app/adapter/d4h.ex) calls Records exactly as it calls D4H,
  over HTTPS with the team's bearer key.
- Records' side is documented in its repo, in `Docs/api.md`.
