# Try a demo

Anyone can try SAR Duty without signing up (#857): a person, an agent showing someone
SAR Duty, or a script checking a live server. Each demo is a copy of Coast Range SAR,
the made-up team (`App.CoastRange`), opened by a link. Its visitor is a team admin
beside Alex Chen. Nobody sees another demo.

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
   `App.Operation.BuildDemoTeam` once, behind a spinner, in about a second. Records makes
   the team from the cast (`App.DemoCast`, `POST /v3/sarduty/demo-teams`) and picks its ids. SAR Duty adds the team, marked
   as the demo in the same transaction, refreshes it like any team, and adds what only it
   keeps (endorsements, ID cards with real codes, away periods, chores), matched through
   Records' ids. A failure removes everything, in Records too, and the page offers Try
   again. A visitor's 3 days count from here.
4. **The banner.** Every page of a demo team has it, for team admins, where View as puts
   its own: when it goes, its link to copy, its Outbox, and Delete this demo. The
   Outbox button counts what arrived since the visitor last opened it
   (`DemoTeam.outbox_seen!/2`), an amber number after the label as tabs show one, and
   has none otherwise. The banner scrolls
   away, so mail arriving also gets a toast under the top bar, on every page but the
   Outbox: "3 emails and 1 text arrived in your Outbox." with a link to it. The
   banner's hook in `Web.UserAuth` waits a second after the first message, so a burst
   of reminders is one toast, and counts only what that burst brought.
5. **The end.** `App.Operation.DeleteDemo` deletes the team through
   `DeleteTeam.purge(team, reason: :demo)`, the same delete as any team's: in Records
   first, which deletes a demo at once with no 7-day hold, then every row in SAR Duty,
   recorded as a `demo_deleted` event, kept 90 days. Then the row with the name, and its
   user. Delete this demo, or `DELETE /api/demos/<token>`, does
   it at once; `App.Worker.DemoTeamsWorker`, every hour, deletes each demo past its time,
   built or never opened.

**Test demos.** A script that checks a live server sends `DEMO_TEST_KEY` as a bearer
token to `POST /api/demos`, with `hours` (2 by default, 24 at most). Its demo is a test
one: outside the IP and live limits, and its hours count from the start. It drives the
demo through the link like a person, reads its Outbox, and deletes it. Fake data on
the real code path, in place of a test activity on a real team.

Demo teams sync only while someone has one open: a team admin's page marks it seen
(`DemoTeam.seen!/2`), and the 10-minute sync takes demos seen in the last hour. They stay
out of the nightly refresh, the sync's team count for Healthchecks, and the admin team
list (`Team.get_all_real/0`). Custom fields stay out of the cast: Records has none.

/agents/demo (`Web.DemoAgentsDoc`) tells agents how to start one, find their way, and
end it.

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
  ID", and letter PDFs have SAMPLE across the page.
- **No Access key tab.** Its key is SAR Duty's, and a real key pasted there would turn
  the copy into a real team. The page is a 404.
- **Agents stay off.** Only a SAR Duty admin turns them on, from the admin team list,
  which leaves demos out.
