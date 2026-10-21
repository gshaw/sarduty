# Chores

Chores are time members give the team outside activities, such as fixing equipment or
board work (#341, closes #11). A member logs each one, a team admin accepts or declines
it, and a team admin sends accepted chores to D4H when they choose. They exist only on a
team with member logins on.

## Chore categories

A member picks a chore category when they log a chore
([ChoreCategory](../lib/app/model/chore_category.ex)). A team admin sets them up under
Settings, Chore categories: a name, which SARVAC hours the chores count for (primary or
secondary), and other D4H tags, picked as on an activity's Change tags page.

- **The hours are a kind, not a tag title.** The event gets the team's primary or
  secondary hours tag (`Activity.hours_tags/1`) when SAR Duty creates it, so a renamed
  hours tag still works.
- **Tags go on an event when it is created and never change.** A category's new tags go
  on the next new event. D4H refuses tag changes on a published activity (#356, #358).
- **A category is archived, never deleted.** Old chores keep it, and members cannot pick
  it. A team admin can restore it.

## Logging and deciding

A member logs a chore at `/teams/:subdomain/me/chores`: a date, minutes, a chore
category, and what they did ([Chore](../lib/app/model/chore.ex),
[SaveChore](../lib/app/operation/save_chore.ex)).

- **Each chore is its own row.** D4H gets one attendance per member per event, but SAR
  Duty keeps every chore with its date and minutes. No start time.
- **A member's date is within the last 60 days and not in the future.** A team admin can
  set any date.
- **A chore counts on the day it was done**, not the day it was logged, so its year is
  the year it was done.
- **Waiting, Accepted, Declined.** A member changes or deletes a chore only while it
  waits, and deletes a declined one once they have read why. Accepted has no tag.
- **A team admin accepts waiting chores in one step** at `/teams/:subdomain/chores`, with
  the Review changes pattern: every row starts selected, and a cleared row stays
  waiting. A chore's own page accepts it, changes any field, or declines it with a
  reason the member sees, in any status.

## The send

Accepted chores wait under Ready to send on the team's Chores page until a team admin
sends them ([SendChores](../lib/app/operation/send_chores.ex)). How often is the team's
choice: a week, a month, or a season's worth at a time. Accepting does not write to D4H.

- **One D4H event per chore category and year in a send**
  ([ChoreEvent](../lib/app/model/chore_event.ex)). One category, since an event takes one
  hours tag. One year, since the event's date decides which tax credit letter counts the
  hours: December and January chores sent together make two events.
- **The event is dated on its last chore**: "Chores: Equipment maintenance, Sep 29 to Oct
  19, 2026", from 00:00 that day in the team's time zone, as long as the largest member
  total.
- **One attendance per member**, from the event's start, for their total. The description
  lists every chore, grouped by member, as HTML: D4H keeps lists and paragraphs but
  strips tables.
- **SAR Duty owns the event and rebuilds it on each send**
  ([BuildChoreEvent](../lib/app/operation/build_chore_event.ex)). Changing or declining a
  sent chore marks its event, and the In D4H table offers Send changes. A sent chore moved
  to another category or year leaves its event and is ready to send again. A send makes
  the title, the times, the description, and each member's attendance match; anyone
  else's attendance is deleted. D4H is read only for ids, so edits made there are
  replaced. An event deleted in D4H is made again.
- **Tags are set when the event is made, and never changed.** Then it is published, last,
  since D4H locks a published activity's attendance. Sending changes makes it a draft,
  changes it, and publishes it again. An event left with no chores stays a draft.
- **Each event is a change set** of source `chores`, so it shows in the activity's and
  each member's history. An event whose send did not go through keeps Send changes, with
  D4H's error beside it.
