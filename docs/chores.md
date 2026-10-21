# Chores

Chores are time members give the team outside activities, such as fixing equipment or
board work (#341, closes #11). A member logs each one in their member area, a team admin
accepts or declines it, and SAR Duty sends accepted chores to D4H every night as one event
per month and chore category. They exist only on a team with member logins on.

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
