# Try a demo

<!-- cspell:ignore Priya -->

Anyone can try SAR Duty without signing up (#857): a person, an agent showing someone
SAR Duty, or a script checking a live server. Each demo is a copy of Coast Range SAR,
the made-up team (`App.CoastRange`), opened by a link. Its visitor is a team admin
beside Alex Chen. Nobody sees another demo.

The decision to use SAR Duty is often an organization's or a senior SAR manager's, so a
demo is an organization too (#963): Coast Range SAR, a second team, Silver Basin SAR
(`App.SilverBasin`), and their organization, WESARA. The visitor is one of WESARA's
organization admins, so they open both Coast Range and the organization's space.

## The cast

- **WESARA**, Western Search and Rescue Association, said "we-SAR-ah"
  (`CoastRange.organization/0`). Its organization admins are Morgan Ellis, executive
  director, and Rowan Pike, office manager; neither belongs to a team.
- **Coast Range SAR** has a member for each case (the `App.CoastRange` moduledoc's Who to
  use). Zoë Lefèvre is its accented name, with attended hours, so she gets a tax letter.
- **Silver Basin SAR** (SBSAR, `silverbasin`) has five members, four incidents and two
  trainings in the past year, all with hours tags, so the organization's totals aren't
  zero and every member gets a letter. Jamie Sato is its team admin. Łukasz Wójcik, Trần
  Minh Châu, and Siobhán O'Connor-Hale are names tax letters once crashed on: a letter
  outside Latin-1, stacked marks, and an apostrophe that breaks HTML, Typst, and CSV
  escaping. No groups, equipment, chores, or cards.

No first or last name repeats between the teams, so a sweep for one team's names never
finds the other's. Their emails are the names in plain letters, like
`zoe.lefevre@example.com` (`CoastRange.email/1`).

The same cast fills the reports sample database (`App.SampleRepo`) and the dev teams
(`tools/dev-teams.exs`): Coast Range SAR at `/teams/coastrange`, Silver Basin SAR at
`/teams/silverbasin`, and WESARA at `/orgs/wesara`, with no demo row, so they keep their
addresses and never expire. A SAR Duty admin opens every organization, so the dev
WESARA has no admin beside Morgan and Rowan.

No email is asked. An agent can't read one, and a form that emails any address is a
way to send mail to strangers. The link is the login instead.

A copy is a SAR Duty Records team ([records.md](records.md)), so the sync, the edits,
and every page work as for any Records team. `App.Model.DemoTeam` is the demo's row,
and a team is a demo when one points at it (`DemoTeam.demo?/1`).

## A demo's life

1. **The start.** `/demo` (`Web.DemoLive`) is one button and an optional name, and
   `POST /api/demos` (`Web.DemoApiController`) is the same for agents and scripts. Both
   call `App.Operation.CreateDemo`, which saves the row and a user for it,
   `visitor-<id>@example.com`. A visitor's demo: 5 an hour per IP, 200 live in all.
   Without SAR Duty's own Records key (`RECORDS_SARDUTY_KEY`), Try a demo is off and the
   home page has no button.
2. **The link.** `/demo/open/<token>` (`Web.DemoController`) logs the browser in as that
   user, remembered, and opens the demo. The token is the demo's id, signed
   (`DemoTeam.link_token/1`), not stored, so the banner can show it again; it stops
   working when the demo goes. It opens the demo in any browser, so an agent can start
   one and hand the link to the person it's helping. Anyone with it is the visitor.
   It is the only way in: an email a visitor types onto a member logs in to nothing
   there (`DemoTeam.team_ids_closed_to_query/1`), or the demo would land in that
   person's account.
3. **The build.** `/demo/building` (`Web.DemoBuildLive`) runs
   `App.Operation.BuildDemoTeam` once, behind a spinner, in about two seconds. Records
   makes both teams from their casts (`App.DemoCast`, a `POST /v3/sarduty/demo-teams`
   each) and picks their ids. SAR Duty adds each team, marked as the demo's in the same
   transaction, refreshes it like any team, and adds what only it keeps on Coast Range
   (endorsements, group rules, ID cards with real codes, away periods, chores,
   templates, and travel), matched through Records' ids. Alex Chen is the team contact.
   Then WESARA's copy, slug `wesara-<demo id>`, with both teams in it and Morgan Ellis,
   Rowan Pike, and the visitor as its organization admins. One shared WESARA would let
   a visitor change settings other visitors see, and see other demos' totals. A failure
   removes everything, in Records too, and the page offers Try again. A visitor's 3
   days count from here. Silver Basin never syncs after the build: nobody opens its team
   pages, and organization admins can't, so its data doesn't change.
4. **The banner.** Every page of a demo team has it, for team admins, where View as puts
   its own: when it goes, a link to WESARA's space, its link to copy, its Outbox, and
   Delete this demo. The
   Outbox button counts what arrived since the visitor last opened it
   (`DemoTeam.outbox_seen!/2`), an amber number after the label as tabs show one, and
   has none otherwise. The banner scrolls
   away, so mail arriving also gets a toast under the top bar, on every page: "3 emails
   and 1 text arrived in your Outbox." with a link to it, but none on the Outbox's own
   list, where a new row is easy to miss too. The
   banner's hook in `Web.UserAuth` waits a second after the first message, so a burst
   of reminders is one toast, and counts only what that burst brought.
5. **The end.** `App.Operation.DeleteDemo` deletes both teams through
   `DeleteTeam.purge(team, reason: :demo)`, the same delete as any team's: in Records
   first, which deletes a demo at once with no 7-day hold, then every row in SAR Duty,
   recorded as a `demo_deleted` event, kept 90 days. Then WESARA's copy, the row with the
   name, and its user. Delete this demo, or `DELETE /api/demos/<token>`, does
   it at once; `App.Worker.DemoTeamsWorker`, every hour, deletes each demo past its time,
   built or never opened.

**Test demos.** A script that checks a live server sends `DEMO_TEST_KEY` as a bearer
token to `POST /api/demos`, with `hours` (2 by default, 24 at most). Its demo is a test
one: outside the IP and live limits, and its hours count from the start. It drives the
demo through the link like a person, reads its Outbox, and deletes it. Fake data on
the real code path, in place of a test activity on a real team.

Demo teams sync only while someone has one open: a team admin's page marks it seen
(`DemoTeam.seen!/2`), and the 10-minute sync takes demos seen in the last hour. Both of a
demo's teams stay out of the nightly refresh and the sync's team count for Healthchecks
(`Team.get_all_real/0`). Adminland's team list shows them under Demos, apart from the
real teams, each demo's Silver Basin after its Coast Range, with whose each is and when
it goes. 200 live demos are 400 Records teams. Custom fields stay out of the cast:
Records has none.

/agents/demo (`Web.DemoAgentsDoc`) tells agents how to start one, find their way, the
organization's space included, and end it.

## What it shows off

A demo is for showing SAR Duty to someone, so each feature has something to see the
moment it opens, staged in `App.CoastRange` (its moduledoc has the cases):

- **The visitor is a member too**: a team leader for 1600 days, with a year of
  attendance, awards, and groups. Their Dashboard's For you to do has their ID card to
  add to Wallet, first aid expiring in 30 days, and travel on Missing hiker to confirm
  (Andrew's ask). Next up asks them to reply.
- **Travel**: Missing hiker is part way, set, some confirmed, one row not set; Overdue
  kayakers is set and confirmed, ready to copy into D4H. Homes and routes are saved, so
  the Travel tab never asks Mapbox.
- **Group rules**: Callout's review takes off Dana, away; Swiftwater team's takes off
  Priya, whose ticket expired. Needs attention counts both.
- **Templates**: Weekly training, Callout (the truck and a radio), and Public education
  booth.
- **Whiteboard notes**, one important, and **saved places** for the activity form.
- Letters have Alex Chen as signer, so only the signature is missing.
- **A form to publish**: WESARA's Task report (`priv/forms/wesara`), on, so the visitor
  fills it on an incident and selects Publish; its PDF says SAMPLE. It is made up, and
  reads only an activity's own fields, since Records teams have no custom fields
  (`App.Operation.AddDemoForms`). The dev WESARA gets it too.

Not staged: certificates waiting for review (Records has no documents, so accepting one
can't attach its file), an activity on now for Take attendance (a demo lasts 3 days), and
a signature.

## What a demo sends

- **Nothing.** Every email a demo team would send goes to its Outbox
  ([outbox.md](outbox.md)) instead: reminders, updates, removals, tax credit letters, and
  the team admin notices, one per member as on a real team. Its links work, so the
  visitor can answer a reminder as the member and see the reply land.
- **No real texts.** A demo team's texts go to its Outbox too: the code that confirms a
  new mobile number (`ChangeOwnPhone`, through `Twilio.send_sms/3` with the team's id).
  Every email and text carries its team, or says it has none, and an unmarked email
  raises ([outbox.md](outbox.md)). A login text is no team's, so text login skips every
  member of a demo team (`Member.current_emails_with_phone/2`) instead, and no text goes
  to a number a visitor typed.

## What a demo shows

- **Cards and letters say Sample.** A visitor can add a member with their own name and
  photo, so the verify site must never call a demo's card or letter real. Both get the
  Sample band from #854 on verify, wallet passes say "Sample card" and "Sample, not real
  ID", and letter PDFs have SAMPLE from the top left corner to the bottom right, in translucent red
  (`tools/sample-mark.py` makes the picture).
- **No Access key tab.** Its key is SAR Duty's, and a real key pasted there would turn
  the copy into a real team. The page is a 404.
- **Agents stay off.** Only a SAR Duty admin turns them on, from a team's admin page.
