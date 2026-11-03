# Try a demo

Anyone can try SAR Duty without signing up (#857). Each visitor gives a name and an
email and gets their own copy of Coast Range SAR, the made-up team (`App.CoastRange`),
for 7 days, as a second team admin beside Alex Chen. Nobody sees anyone else's copy.

A copy is a SAR Duty Records team ([records.md](records.md)), so the sync, the edits,
and every page work as for any Records team. `App.Model.DemoTeam` is the visitor's row,
and a team is a demo when one points at it (`DemoTeam.demo?/1`).

## A demo's week

1. **The form.** `/demo` (`Web.DemoLive`) takes a name and an email, and
   `App.Operation.RequestDemo` saves the row and emails a link with a six-digit code. The
   email holds no name: anyone can type any address, so it says nothing they chose. One
   demo per email; asking again sends a new code to the same demo. Limits: 5 requests an
   hour per IP, 200 live demos in all. Without Records' demo key (`RECORDS_DEMO_KEY`),
   Try a demo is off and the home page has no button.
2. **The link.** `/demo/open/:id?code=…` (`Web.DemoController`), or the code typed on
   `/demo`, logs the visitor in. The code works for 24 hours and dies after 5 misses. It
   works more than once, since a mail app that opens links to check them would use up a
   single-use one. `/demo` checks a typed code itself, so a blank or wrong one stays on the
   code step, and keeps that step in the URL (a signed `sent` token) so a refresh keeps it
   too. The login is remembered, like a login code's Remember me, as the demo lasts 7 days.
3. **The build.** `/demo/building` (`Web.DemoBuildLive`) runs
   `App.Operation.BuildDemoTeam` once, behind a spinner, in about a second. Records makes
   the team from the cast (`App.DemoCast`) and picks its ids. SAR Duty adds the team, marked
   as the demo in the same transaction, refreshes it like any team, and adds what only it
   keeps (endorsements, ID cards with real codes, away periods, chores), matched through
   Records' ids. A failure removes everything, in Records too, and the page offers Try
   again. The 7 days count from here.
4. **The banner.** Every page of a demo team has it, for team admins, where View as puts
   its own: when it goes, View as Cameron Ruiz, Sign up your team, and Delete this demo.
5. **The end.** `App.Operation.DeleteDemo` deletes the team in SAR Duty and Records, the
   row with the name and email, and the visitor's user unless they are on a real team.
   Delete this demo does it at once and logs out; `App.Worker.DemoTeamsWorker`, every
   hour, emails the day before and deletes on day 7, built or never opened.

Demo teams sync like any team, so edits come back, but stay out of the nightly refresh,
the sync's team count for Healthchecks, and the admin team list (`Team.get_all_real/0`).
Custom fields stay out of the cast: Records has none.

## What a demo sends

- **Everything goes to the visitor, once.** A team's email goes through
  `App.Mailer.for_team/3`, which sends a demo team's to the visitor alone, with
  [Demo] before the subject and a first line saying whose copy it is. A send to 15
  members is one email: `DemoTeam.one_copy/2` lets the first member's go and marks the
  rest sent. That covers reminders, updates, removals, tax credit letters, and the team
  admin notices. An activity email's buttons answer for that member, so the visitor sees
  the reply land. The page's toast says where the copy went.
- **The backstop.** `App.Mailer.deliver/2` refuses a demo team's email to anyone but
  its visitor, so a mailer that forgets `for_team/3`'s redirect still sends nothing to a
  stranger. A new team email still needs `for_team/3`, or the backstop can't tell whose
  it is.
- **Never a text.** Text login skips every member of a demo team
  (`Member.current_emails_with_phone/2`), and a demo team's member cannot add a mobile
  number (`ChangeOwnPhone`), so no text goes to a number a visitor typed.

## What a demo shows

- **Cards and letters say Sample.** A visitor can add a member with their own name and
  photo, so the verify site must never call a demo's card or letter real. Both get the
  Sample band from #854 on verify, wallet passes say "Sample card" and "Sample, not real
  ID", and letter PDFs have SAMPLE across the page.
- **No Access key tab.** Its key is SAR Duty's, and a real key pasted there would turn
  the copy into a real team. The page is a 404.
- **Agents stay off.** Only a SAR Duty admin turns them on, from the admin team list,
  which leaves demos out.
