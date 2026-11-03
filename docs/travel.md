# Travel

How each attended row got to an activity, and the km it counts (#230). It took the
Mileage report's place on the activity, in its Actions.

## How it works

- **Round trips come from SAR Duty's copy.** `App.Operation.BuildMileageReport` reads the
  activity's attended rows (`Attendance.attended/2`), the team's yard, and the activity's
  location, and never D4H. Mapbox finds each home and each one-way route once, and both
  are saved: a home in `home_coordinates`, looked up again only when the member's
  address changes, and a route in `route_distances`. A place or route Mapbox found none
  for is saved as none; one it didn't answer for is asked again next visit.
- **One trip per attendance row, not per member.** A member on two days of a search drove
  twice, so each row gets its own km in D4H. In South Fraser's copy, 34 of the 38 incident
  cases of a member with two attended rows are on different days.
- **A team admin sets them** on Travel, laid out like Remove members: check rows, then
  Set to ICP, yard, or passenger (0 km), or type km. `App.Operation.SetTravel` saves a
  `trips` row with the km as it was then, so a later address change never moves it. A
  row with no route to where it drove is skipped, and the toast says to type its km.
- **Trips are keyed by D4H's attendance id**, which outlives the local row, so a row the
  refresh deletes and copies back keeps its trip.
- **Members check theirs** before the copy into D4H. A trip a team admin set shows on
  the activity's page as Your travel, with who set it, That's right, and Change (the
  same four ways). The Dashboard's For you to do lists each activity with one unchecked,
  until it's checked or the activity is published. Either answer sets `checked_at`; a
  team admin setting the row again clears it, except on the admin's own rows. Travel
  marks checked rows, and Change activity counts the members who haven't.
- **Email members to check** is a button on Travel, never sent on its own. It reaches
  each member with an unchecked trip, an email, and a login (member logins on, not
  retiring). Each is an `activity_updates` row of kind `:travel_check`, sent by
  `SendActivityUpdateWorker` like an update, so a refusal is retried, and a member who
  checks first, or an activity published first, gets nothing. Travel says when it last
  went. A team without member logins gets no button: its members can't log in to check.
- **Publishing locks travel**, as it does attendance. To change it, a team admin
  unpublishes first. Change activity says how many rows aren't set, beside the Published
  box: a note, never a block.

## Into D4H

D4H's API has no mileage, so SAR Duty can't write it. Travel's folded "Copy into D4H"
section holds text for a browser agent such as Claude in Chrome, from what's saved:
the activity's reference and link, how to fill each km box without saving, then one line
per row set (name, attendance times, km) and the rows to leave alone
(`App.ViewData.ActivityTravel.d4h_prompt/3`). Andrew Wallwork at South Fraser wrote the
first version. A Records team gets no copy: it has no D4H.

## Not in this

- Driving time: it waits for en route and home safe (#735, #736).
- Guessing how a member got there from scans, team vehicles, or On my way.
