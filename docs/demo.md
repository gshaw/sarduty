# Try a demo

Anyone can try SAR Duty without signing up (#857). Each visitor gives a name and an
email and gets their own copy of Coast Range SAR, the made-up team (`App.CoastRange`),
for 7 days, as a second team admin beside Alex Chen. Nobody sees anyone else's copy.

A copy is a SAR Duty Records team ([records.md](records.md)), so the sync, the edits,
and every page work as for any Records team. `App.Model.DemoTeam` is the visitor's row,
and a team is a demo when one points at it (`DemoTeam.demo?/1`).

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
