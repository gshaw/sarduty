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
- **A chore belongs to the month it was done in**, not the month it was logged.
- **Waiting, Accepted, Declined.** A member changes or deletes a chore only while it
  waits, and deletes a declined one once they have read why. Accepted has no tag.
- **A team admin accepts waiting chores in one step** at `/teams/:subdomain/chores`, with
  the Review changes pattern: every row starts selected, and a cleared row stays
  waiting. A chore's own page accepts it, changes any field, or declines it with a
  reason the member sees, in any status.
