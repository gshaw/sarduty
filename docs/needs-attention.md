# Needs attention

The team home's list of work waiting for a team admin (#205): counts of live data, never
stored. `App.ViewData.TeamAttention` turns rows into items and is pure;
`App.ViewData.TeamDashboardViewData` reads the rows. The page shows 7 items, danger
first, then warnings, then info, and "+2 more" under them shows the rest in place until
the page reloads. Snoozed items don't count toward the 7. The MCP tool `needs_attention`
lists every one.

## Snoozing an item

A team admin snoozes an item until tomorrow, for a week (picked), or for a month (#751),
with the alarm before its chevron. No forever. The snooze is the team's: every team
admin stops seeing the item, and "1 snoozed" on the card's title row lists who snoozed
it, until when, and Show again.

Only the decision is stored. `attention_snoozes` holds the item's key, the ids of what
it counted when snoozed, and when it ends. The item stays hidden while the snooze lasts
and its ids now are a subset of those saved (`TeamAttention.items/4`). Something leaving
it is progress and keeps it hidden; anything new brings it back at once. A count would
miss a swap, and the title changes with every one done.

`SnoozeAttentionItem` reads the ids from the item, never from the browser. The MCP tool
lists snoozed items last, with `snoozed_until`, and the nightly prune deletes snoozes a
day after they end.

## Which items can be snoozed

Snooze is for work that waits on people outside SAR Duty and can sit for weeks. Each
other kind of item stays on the list until it's done:

| Item                                                       | Snooze | Why                                |
| ---------------------------------------------------------- | ------ | ---------------------------------- |
| Drafts, drafts missing required fields                     | Yes    | Waits on activity leads            |
| Awards expiring                                            | Yes    | Waits on members renewing          |
| Members missing details                                    | Yes    | Waits on members replying          |
| Members not attended                                       | Yes    | Check-ins take weeks               |
| Retiring members holding items                             | Yes    | Waits on gear coming back          |
| Retiring members holding nothing                           | Yes    | Can wait on the board or paperwork |
| Activities with no hours tag, this year                    | Yes    | Tidied at year end                 |
| Activities with two hours tags, this year                  | Yes    | Tidied at year end                 |
| Can't refresh, key rejected, a group deleted               | No     | Something is broken                |
| Retiring members can still log in to D4H                   | No     | A risk while it lasts              |
| Certificates, chores to accept                             | No     | A member waits on the team admin   |
| Attendance to send, group rule changes, chores out of date | No     | One step in SAR Duty               |
| No-shows to follow up                                      | No     | Leaves on its own after a week     |
| Tax credit letters, last year's hours tags                 | No     | Has a deadline                     |
| Team name too long                                         | No     | No ids to come back on             |

## Adding an item

1. Read the rows in `TeamDashboardViewData.attention_rows/4`. Scope by `team_id`, and
   reuse the query the item's link opens, so the count and the list match.
2. Build the item in `TeamAttention`: `key`, `level`, `title` with its count, `detail`
   saying where the fix happens, and `action`. Link it in `TeamDashboardLive`.
3. Decide snooze with the table above. To let a team admin snooze it, read sorted ids instead of a
   count, put them on the item as `ids`, and add a line to `@back_sooner` saying what
   brings it back. Ids are local: members, activities, or awards.
4. Add the key to one of the two lists in `TeamAttentionTest`'s "every item that waits on
   people can be snoozed" test. It fails until you do.
