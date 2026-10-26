# Chores

Chores are time members give the team outside activities, such as fixing equipment or
board work (#341, closes #11). A member logs each one from Your membership, and a team
admin accepts or declines it. Accepting sends it to D4H, on its chore category's
activity for the month. They exist only on a team with member logins on and Let members
log chores checked under Member logins in team settings; every team starts with it off
(#463).

## Chore categories

A member picks a chore category when they log a chore
([ChoreCategory](../lib/app/model/chore_category.ex)). A team admin sets them up under
Settings, Chore categories: a name, which SARVAC hours the chores count for (primary or
secondary), and other D4H tags, picked as on an activity's Change tags page.

- **The hours are a kind, not a tag title.** The event gets the team's primary or
  secondary hours tag (`Activity.hours_tags/1`) when SAR Duty creates it, so a renamed
  hours tag still works.
- **Tags go on an event when it is created and never change.** A category's new tags go
  on the next month's event. D4H refuses tag changes on a published activity (#356,
  #358).
- **A category is archived, never deleted.** Old chores keep it, and members cannot pick
  it. A team admin can restore it.

## Logging and deciding

A member logs a chore at `/teams/:subdomain/me/chores`: a date, minutes, a chore
category, and what they did ([Chore](../lib/app/model/chore.ex),
[SaveChore](../lib/app/operation/save_chore.ex)).

- **Each chore is its own row.** D4H gets one attendance per member per event, but SAR
  Duty keeps every chore with its date and minutes. No start time.
- **A member's date is within the last 60 days and not in the future.** A team admin can
  set any date that has passed. Never the future, where D4H counts the hours as signed
  up, not attended.
- **A chore counts on the day it was done**, not the day it was logged, so its month
  and year are the ones it was done in.
- **Waiting, Accepted, Declined.** A member changes or deletes a chore only while it
  waits, and deletes a declined one once they have read why. Accepted has no tag.
- **A team admin accepts waiting chores in one step** at `/teams/:subdomain/chores`, with
  the Review changes pattern: every row starts selected, and a cleared row stays
  waiting. A chore's own page accepts it, changes any field, or declines it with a
  reason the member sees, in any status, and links its D4H activity.
- **The Chores page splits chores by status**, Waiting, Accepted, and Declined, opening
  on Waiting. Accepted lists each D4H activity, newest month first, with its chores
  under it, so every chore stays one click from its page. Before this, an accepted chore
  showed only in its activity's totals and had no way back to its page (2026-10-23).
  After a change, the page opens on the view the chore is in now. Search finds a chore
  by its words.

## The send

Every team admin decision sends to D4H at once
([SendChores](../lib/app/operation/send_chores.ex)): accepting a chore, changing one, or
declining one. There is no separate send step. An earlier version made one activity per
send, so a team admin who accepted chores every day got an activity a day (2026-10-23).

- **One D4H event per chore category and month**
  ([ChoreEvent](../lib/app/model/chore_event.ex)). One category, since an event takes one
  hours tag. One month, so the event stays in one tax year and in the month its chores
  were done. Each decision puts the team's accepted chores on their months' events,
  making one when there is none, and sends the events that changed. No setting picks the
  period: Andrew said how often D4H gets events does not matter, and leaned to monthly
  (#341).
- **The event is titled and dated for its month**: "Chores: Equipment maintenance,
  October 2026", at 00:00 on the 1st in the team's time zone. It used to sit on the last
  chore's day, so it moved with each chore; on the 1st it stays put and keeps D4H's
  calendar tidy (team admin, 2026-10-24). It lasts no time at all: members' hours are on
  their attendance, and an event as long as the largest total looked like a real
  activity on D4H's calendar (Andrew, 2026-10-23). D4H and Records take an event that
  ends when it starts, and attendance that runs past its end (tried on #02228,
  2026-10-23). Never in the future, where D4H counts attendance as signed up: the 1st
  is never after a chore in its month.
- **One attendance per member**, from the event's start, for their total. The description
  lists every chore, grouped by member, as HTML: D4H keeps lists and paragraphs but
  strips tables.
- **SAR Duty owns the event and rebuilds it on each send**
  ([BuildChoreEvent](../lib/app/operation/build_chore_event.ex)). A send makes the title,
  the times, the description, and each member's attendance match; anyone else's
  attendance is deleted, and so is a member's second row, since D4H lets a member attend
  one activity twice (tried on #02228, 2026-10-21). D4H is read only for ids, so edits
  made there are replaced. An event deleted in D4H is made again.
- **Declining is the undo.** A declined chore leaves its event, and the send takes its
  hours off. An event left with no chores stays a draft with no attendance, since D4H's
  API cannot delete an event.
- **Tags are set when the event is made, and never changed.** Then it is published, last,
  once its attendance is in. Sending changes makes it a draft, changes it, and publishes
  it again.
- **When D4H will not publish**, the event stays a draft. The send counts as done, with a
  note beside it, since SAR Duty counts a draft's hours all the same. D4H does not: its
  statistics take only published activities, so the team publishes the draft in D4H.
- **Why South Fraser's publish failed.** D4H answered 409 to every publish from the API
  (#02228, 2026-10-17 and 2026-10-21) while D4H's own Approve button worked. BCSARA, the
  organization, had set a forced approval message long ago, and South Fraser's own
  approval message setting, in D4H's admin area, was off. Turning it on fixed the
  publish (2026-10-25). Another BCSARA team that turns on chores may need the same, so
  on that 409 the note says to turn the setting on (#575).
- **Nothing locks an event.** D4H's `approved` flag mirrors `published` on every team seen
  (#358), so the first version, which stopped sending an approved event, stopped at the
  first published one.
- **A send that does not go through** leaves its event with changes to send and D4H's
  error beside it. The Chores page then shows Send changes, and the team home a warning.
  The next decision tries it again too.
- **A team's sends run one at a time** (`:global.trans`), so two team admins accepting at
  once cannot make a month's event twice. Production is one machine.
- **Each send of an event is a change set** of source `chores`, so it shows in the
  activity's and each member's history.

## Where else chores show

- **Team home**: for team admins, "N chores to accept" under Needs attention, and a
  warning when a chore activity is out of date in D4H; the waiting count shows beside
  Chores in the side navigation. For a member, a declined chore under For you to do until
  they delete it.
- **Activities**: chore activities are their own kind, Chores, though D4H holds them as
  events (#575). A Chores tile beside Events lists them, with each one's members' total as
  its duration, since the activity lasts no time. All includes them; Events leaves them
  out. The tile shows on a team with chores on, or one with chore activities in the view. The
  activity's page says Chores too. SAR Duty knows them by its chore events
  (`ChoreEvent.totals/1`), never by tag: each category picks its own tags.
- **Your membership**: the member's 5 latest chores, with New chore and a link to all of
  them (#406).
- **The tax credit letter and the year page** add chore rows up and never put them on
  the timeline where overlapping time counts once (#584): every chore row starts at
  00:00 on the 1st, so a member's categories would overlap each other. A sent chore's
  activity carries its category's hours tag, which says primary or secondary. #592
  explains the count publicly.
