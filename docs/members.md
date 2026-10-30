# Members

The members list and a member's page, for team admins and, read only, for members (#440),
and member logins.

## The members list

`/teams/:subdomain/members` ([MemberCollectionLive](../lib/web/live/member_collection_live.ex),
[MemberFilterViewModel](../lib/app/view_model/member_filter_view_model.ex)) answers
questions with general filters and sortable columns rather than one Needs attention item
each (#367): "who in Callout is drifting away?" is Group: Callout sorted by Last attended.

- **Last attended** is the start of the latest activity the member attended, any kind
  (incidents, exercises, events), not deleted. Showing up to anything is the sign it is
  for. It comes from a join on `Member.last_attended_query/1`, so it sorts, and never
  attended sorts first going up. The member's page shows the same date.
- **Period** sets what Activities and Duration count, and limits the list to members on
  the team at some point in it: All, the last 30, 60, 90, 180, or 365 days (`when=90d`),
  or a year (`when=2026`, the default this year). It replaced Year, so old year links
  open the same list.
- **Standing** filters by [standing](#standing): Not retired (the default, `current`),
  Active, Away, Retiring (with a Retiring group), Retired, Not a person, or All: a
  member's path, then Not a person, which is no step on it. It was Current until 2026-10-20, which
  people mixed up with Active. It replaced Status, and old
  `status=` links are not kept (decided 2026-10-19). Its column says "Away until Mar 1"
  and sorts by that day, with retired members last.

- **Attended** lists members whose attendance clock is older than a time frame. The
  clock counts from the latest of their last activity, the day they joined, the end of
  an away period that has started, and their latest check-in (`Member.not_seen_query/4`).
  When the clock starts from something other than the last activity, the **Last
  attended** cell says which under the date: "Back from leave Sep 2", "Checked in
  Oct 3", or "Joined Jun 1" (decided 2026-10-19; a Clock starts column mostly repeated
  Last attended). The filter guesses at nothing: bots and members on leave are left out
  by the Standing filter, not by the clock.

Standing, Period, and Group sit in the filter bar's row. Details and Attended wait
behind **More filters** until one is on, so the row doesn't wrap and a link such as
the home item's still shows every filter it sets.

No column chooser. A filter changes the rows, not the columns (2026-10-25). There is no
Standing column: the Member column's badge shows it (#740). Two columns come
with a filter: Retired when the Standing filter can show retired members, since no
other row has a date, and Missing with Details: Missing, since it says why each row
matched. ID hides on narrow screens.

## Changing a member's details

A team admin changes a member's details on every team, from Change member in the
member's Actions (`/members/:id/edit`, decided 2026-10-29). The form has name, ID, Role,
email, mobile phone, address, joined date, and status: Operational, Not operational, or
Observer, D4H's three. Saving is one `update_member` row naming only what changed,
through [SaveMember](../lib/app/operation/save_member.ex) and ApplyEdit, which sends a D4H
team only those fields (`ApplyEdit.d4h_takes?/1`). A D4H team's form has no Team admin
box, photo, or Mark as retired: D4H sets access, photos, and leaving in its web app, and
Retiring is its own steps ([Retiring](#retiring)). Adding a member is a Records team's
only ([records.md](records.md#editing-records)).

- **Role** is D4H's free-text `position`, so teams drift: South Fraser had 45 roles
  across 93 members. Role is the combobox with `free_text`: it lists the team's roles,
  most held first (`Member.roles/1`), the way a filter's combobox lists its options, and
  still takes a new one. D4H's structured `roleId` is not copied.
- **Email** decides who can log in: SAR Duty matches a login to a member by email, so
  its hint says so. Changing it moves the login to the new address.

## Standing

A member's **standing** says whether the team expects them to show up now (#366):
**Active**, **Away** for a dated period such as leave, **Retiring**, **Not a person**,
or **Retired**. Decided 2026-10-18; the issue has the reasons. Retired was added
2026-10-19, Retiring 2026-10-27 (#514).

- **One home.** [Standing](../lib/app/model/standing.ex) holds the order, Retired, Not a
  person, Retiring, Away, Active, where the first that applies wins. `Standing.of/5`
  works it out for one member and `Standing.dynamic/1` in SQL for a list, and a test
  runs every mix through both. Nothing else copies the order.
- **Retiring is read from a D4H group; SAR Duty owns the rest.** Away periods and Not a
  person never go to D4H. Teams on D4H and on SAR Duty Records work the same.
- **Retiring** (#514) is a current member in the team's Retiring group. They no longer
  count as a member: see [Retiring](#retiring).
- **Access** (`access=some` or `none`, behind More filters, team admins only) keeps the
  members D4H lets log in, or those with No access.
- **Items** (`items=held` or `none`, behind More filters, team admins only) keeps the
  members who hold any of the team's equipment, retired items too, or those who hold
  none. Needs attention's "2 retiring members hold no items" opens
  `standing=retiring&items=none`, the members to retire now.
- **Retired comes from D4H**: D4H marks the member Retired, or gives them a leave date
  that has passed, or stops listing them. The same test as `Member.current_query/2`. It is read, never stored or set, and wins over
  the rest. A retired member gets no away periods. Group rules and the attendance check
  don't offer it: they only ever add or count current members.
- **Dates, not jobs.** [MemberAwayPeriod](../lib/app/model/member_away_period.ex) stores
  a first and last day on the team's clock and a short reason the team admin writes,
  such as "Parental leave", and `MemberAwayPeriod.standing/4` works out standing when
  read. No job flips a member back.
- **The reason is free text, not a list** (decided 2026-10-18). A fixed list of
  categories guessed at teams' cases and nothing read it. The hint asks for no medical
  details.
- **Not a person** is the old toggle, unchanged in `members.not_a_person`. It wins over
  an away period. **Active** is the absence of the others and is never stored. What it
  does is under [Not a person](#not-a-person).
- The member's **Standing** tab lists away periods, past ones too, with a form to add one
  and buttons to end one today or delete it. Any team admin can. With a Retiring group it
  has **Mark as retiring** or **Remove from Leavers** (the group's own name), one
  `add_group_member` or `remove_group_member` row through `SetGroupMember`, as the
  Groups tab sends, and the line "Avery Chen holds 3 items. Retire them in D4H once
  every item is back." The header on every member tab badges a standing other than
  Active: amber for Away until a date and Retiring, grey for Retired and Not a person. Each change goes in the member's history, from
  `member_standing_changes`, which keeps the reason and dates.
- A member away sees the same Away badge on Your membership, as a reminder. Members never
  see the reason, which is `redact: true`. Nobody else who logs in as a member sees an
  Away badge, count, filter, or sort (#440): away is often leave. They see every other
  standing, Not a person included.
- **Check-ins** are on the same tab: a team admin records the day they reached a member
  and what they heard ([MemberCheckIn](../lib/app/model/member_check_in.ex)). It
  restarts the member's attendance clock and changes nothing else: not standing, not
  groups, nothing in D4H. If the call turns up leave, the admin adds an away period too.
  Any team admin can delete one recorded by mistake, and the clock goes back without it.
  Members do not see check-ins, and the note is `redact: true`.

Nothing leaves a group or a list for standing unless a rule written on its page says so.
These stay as they were, since a bot cannot attend or be added to an activity, and skip
members marked not a person or retiring with no rule (`Member.counted_query/1`): Add
members and a template's groups (`InviteMembers`), the home page's counts and charts,
the missing details filter, and the member list on Take attendance. Retiring members
skip more than that; see [Retiring](#retiring).

### Not a person

One rule, decided 2026-10-30, and the switch's hint says it: **a bot or shared account
logs in, gets email, and has the access D4H gives it, like any member. SAR Duty never
counts it as one of the team's people or offers it when you pick people.**

- **Counted or picked** (`Member.people_query/1`, through `counted_query/1`): member
  counts, Missing details, Add members, a template's groups, and Take attendance's list.
- **Like any member**: logging in, as a team admin when D4H makes it an Owner or Editor;
  Team admins and team admin email, with its badge; reminders; its own page and history.

So a sign-in kiosk with its own email, such as a team's `kiosk@` account, logs in and
opens Take attendance. Until 2026-10-30 Not a person also blocked logins, and the team
key's account was left out of Team admins by a name match on "SAR Duty". Both are gone:
a team marks its key's account Not a person like any other bot.

### Retiring

A retiring member is on their way out. A team admin has put them in the team's
**Retiring group**, picked in Settings → Members (`teams.retiring_d4h_group_id`), and
D4H hasn't retired them yet, usually because they still hold the team's items: D4H
refuses to retire a member who does. It can last weeks. Decided 2026-10-27 (#514) and
2026-10-28 (#683).

**The rule: a retiring member is no longer a member.** Everything that counts,
contacts, invites, or lets members in skips them (Andrew, 2026-10-28). Only the pages a
team admin uses to finish retiring them still show them.

| Skips retiring members                                                                                                               | Through                                              |
| ------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| Logging in as a team admin, MCP tokens, Team admins, the last team admin check, and team admin email                                 | `Member.managers_query/2`                            |
| Logging in as a member                                                                                                               | `Member.counted_query/1` in `Member.get_logins/2`    |
| Dashboard counts and charts, Missing details, Add members, a template's groups, Take attendance, and an organization's member totals | `Member.counted_query/1`                             |
| Reminders                                                                                                                            | Send reminders names them under "Who doesn't get it" |

Still shown: the Members list (the Retiring tile, and Not retired, its default), their
member page and history, Equipment's With retiring members, and Needs attention. Group
rules leave them in a group unless a rule on its page says "Standing is …" (above).

**A new query that counts, contacts, invites, or lets members in skips retiring
members.** Use `Member.counted_query/1`, or `Member.managers_query/2` for team admins.
Don't read `group_members` for it yourself. Contacting skips retiring members only:
reminders still go to a member marked not a person, on purpose (#740), and every member
table shows them with the Not a person badge. One bar for logins, Team admins, and team
admin email (2026-10-28, #683): a team admin marked not a person logs in and is listed,
with the badge (2026-10-30; see [Not a person](#not-a-person)).

**The steps, in order.** Needs attention and the member's Standing tab lead a team
admin through them.

1. **Mark as retiring** on the Standing tab: one `add_group_member` row through
   `SetGroupMember`. SAR Duty access ends on their next page, since access is checked on
   every page load, so do it before telling them. The team's only team admin is refused,
   from any page that adds to the Retiring group, since nobody could log in as team admin
   after. Your membership's list of the items they hold
   doesn't justify the access.
2. **Set their access to No access in D4H.** SAR Duty can't: D4H sets access only in
   its web app (a Records team can, on Change member). Until it's done, two red notices
   say so. Needs attention's one danger item, red and first in the list: "2 retiring
   members can still log in to D4H", opening `standing=retiring&access=some`. And a red
   banner on every tab of that member's page, with an Open in D4H link. Access is
   the synced `d4h_permission`, anything but No access (`Member.d4h_access?/1`); a
   member whose permission D4H didn't send isn't counted.
3. **Get the items back.** Needs attention's "1 retiring member holds 3 items" opens
   Equipment's With retiring members.
4. **Retire them in D4H.** Needs attention's "2 retiring members hold no items" opens
   `standing=retiring&items=none`, and its hint, "Retire them in D4H.", is what stops a
   member staying Retiring for good. D4H sets No access when it retires someone, and
   they become Retired.

**Guards.** Mark as retiring refuses the team's only team admin, who would lock the team
out. The Retiring group can't have group rules, since "Standing is Active" on it would
take out every member, and settings offer only groups without them. If D4H deletes the
group, nobody is Retiring and Needs attention says so until a team admin picks another.
Retiring is read from `group_members`, never stored, and no job.

## The attendance check

Needs attention lists members who have not attended in a while, so someone can check in
with them (#247, #366). It is three choices on **Settings → Members**, beside the
Retiring group, decided 2026-10-18: no live summary.

- **Members who have not attended**: Off, 30, 60, 90, 180 days, or 1 year
  (`teams.not_seen_days`).
- **Watch**: all current members, or one group (`teams.watch_d4h_group_id`, a D4H id like
  group rules). Anything more complex is a group with group rules.
- **Standing**: which standings to watch (`teams.watch_standings`), Active by default.

The home item is "4 members of Callout have not attended an activity in 90 days", linking
to `/members?attended=90&group=<id>&standing=active`. Its count is
`MemberFilterViewModel.count/3` on the same params, so it always matches the list. If D4H
deletes the watched group, the item is a warning that says so, and settings keep the
group, named as gone, until a team admin picks another. It never watches everyone
quietly.

The old hidden rules went with it: members who joined within the time frame (now part of
the clock), the team key's "SAR Duty" member, and members with no email, mobile phone, or
attendance. Existing teams watch all members who are Active. A bot nobody marked now shows
on the list, on purpose: marking it Not a person fixes it everywhere. The "looks like a
bot" hint stays on the member's Standing tab.

## Qualifications and activities

A member's qualifications and activities look the same on their own page and on a team
admin's member page, from one query and one component each (#308, #339, decided
2026-10-20). Org pages can use them later: each takes rows and a time zone, not a team.

- **Qualifications** come from `MemberRecords.qualifications/2`: one table, one row per
  qualification, soonest expiry first, then those with no end, then Expired (muted). One
  that expires within 60 days, the app's one expiring window
  (`BuildGroupRulePreview.expiring_days/0`), gets a warning tag with its days left ("30
  days"), as a group's expiring members do. No banner says it again (decided
  2026-10-21): the row is first in the table, and the Dashboard's For you to do already
  says what to do. The words are
  [Web.QualificationText](../lib/web/qualification_text.ex), so every page says the same
  thing.
- **No end is a blank cell** (decided 2026-10-22), not "Does not expire": most rows have
  no end, and the same words on each made the list read long.
- **Every row, on both pages** (decided 2026-10-22). No shorter list on Your membership
  with the rest a click away. On South Fraser's data a member has about 8, so a split
  would cost most members a click to save a few rows; only 15 of 91 have more than 20.
- **Certificates** (#314, decided 2026-10-22). An award with a document in D4H gets a
  Certificate link under its title, on Your membership and on the admin's tab. Each has
  its own route, `/me/qualifications/:id/certificate` and
  `/members/:id/certificates/:award_id`, which finds the award through the member and
  team, then fetches the file from D4H with the team's key: nothing is stored, and the
  team key reads RESTRICTED documents too. PDFs and images open in the browser; any
  other file downloads, and every file is sent sandboxed so it can't run as a page. Only
  the latest award's certificate is linked. Records serves none until uploads come.
- **No groups** (decided 2026-10-20). #308 asked for groups by expiry. On South Fraser's
  data, 11 of 84 members had anything expiring within 60 days, never more than 1, and
  most groups held 1 or 2 rows under their own heading. A tag finds the one that matters.
  `<.table groups={…}>` stays for lists where each group holds several rows.
- **One row per qualification**, from its latest award: when it expires (or expired) and
  the year it was first held. Team admins also get an Earlier awards column, with Remove
  on a team on SAR Duty Records. The admin's tab lost its Start column.
- **No component of their own** (decided 2026-10-20). Pages pick their columns from one
  set of rows, and the table does the rest. A two-line list wasted space.
- **Activities** are a table too: day, title linked to the activity's page in SAR Duty
  (#406), kind, and time there, newest first. No groups by month (decided 2026-10-20): a
  member attends a median of 19 a year, so a month heading sat over about 2 rows, and the
  date already says the month. Not by kind either, since every row shows its kind.
- **A team admin's Attendance tab keeps its table.** It searches, sorts, filters by hours
  and activity tag, and pages by 50, and links to SAR Duty's own activity page. Its years
  come from `MemberRecords.years/2`, as the member's own page lists them.

## Member logins

A team admin turns on member logins in **Team settings → Features**. Then every
current member of the team can log in with the email or mobile number D4H has for them
(#156). They open the same team space as its team admins, and see the pages marked for
members ([navigation.md](navigation.md)). Their own pages are under
`/teams/:subdomain/me`:

| Page            | Path                   | What it holds                                                     |
| --------------- | ---------------------- | ----------------------------------------------------------------- |
| Your membership | `/me`                  | A year's activities, qualifications, ID card, letter, and more    |
| The year page   | `/me/activities?year=` | A year's hours, letter, map, and numbers, and every activity      |
| Contact details | `/me/details`          | Mobile number, mailing address, and emergency contacts, to change |

Members don't change their email: teams keep it consistent, and team admins change it in
D4H. Logins are designed in issue #156; the pages in #389, and one page in #406.

### Your membership

`/teams/:subdomain/me` ([MeLive](../lib/web/live/me_live.ex)) is one page (#406),
replacing the overview of #389 and taking in its pages: ID card, Qualifications, Hours,
Tax credit letters, and Milestones are gone, with no redirects. It opens with the same
header as the team member page (`<.person_head>`, `/styles/person-head`): their D4H photo
in a circle, or their initials when D4H has none (`/members/:id/image`), their name, an
Away badge while they're away, and "Ground searcher · Joined March 2019 · Last attended
Sep 30, 2026". Neither page shows the member ID: teams number members in very different ways.

- **Main column**: one year of their activities (#576), this year unless the year menu
  beside Activities picks another (`?year=`, the year page's years). Its total, primary,
  and secondary hours, counted as the letter counts them, since members read them to see
  where they stand; then its 10 latest activities, and "All 41 activities in 2026" to
  the year page. A year with nothing says "No activities in 2027", so in January they
  pick last year from the menu. Then their qualifications: Qualification and Expires,
  from the same rows a team admin sees. Then the equipment they hold, when they hold
  any, so they know what to bring back: the table a team admin sees on their Equipment
  tab, retired items too, with no links (#490,
  [equipment.md](equipment.md#items-members-hold)).
- **Sidebar**, sections split by space, no boxes (`/styles/card`): the ID card, when the
  team has ID cards on, then the latest tax credit letter to download, with its hours on
  the year page so they aren't mistaken for the year's above; then contact details
  and every milestone, newest first. On a phone the ID card and letter come first, then
  the main column, then contact details and milestones.
- **Contact details** are the mobile number, address, and emergency contact, from the
  copy, so the page never reads D4H (#423).
- Each part says why it is empty for a new member.
- **Milestones**: hours (100, 250, 500, 1,000, then every 1,000), years on the team (1, 5,
  10, then every 5), and incidents (the first, 10, 25, 50, 100, then every 100), each
  dated by the day it was reached: [Milestones](../lib/app/view_data/milestones.ex),
  pure. They're worked out when the page loads, from `Attendance.attended/2`,
  `joined_at`, and away periods, so past ones show on day one and nothing is stored.
  Years leave out the days away: teams reopen a rejoining member's D4H record, and a team
  admin adds the gap as an away period. Hours count every attended activity, not only
  tagged ones. A plain dated list: no badges, graphics, or levels (decided 2026-10-20).
- **Team admins see what members hold** (#490). A member who holds something gets an
  Equipment tab, with no count in the sidebar (2026-10-24): see
  [equipment.md](equipment.md#items-members-hold).
- **Team admins see milestones too** (2026-10-23). The member sidebar on every member
  tab shows the latest and links to the team's Milestones page,
  `/teams/:subdomain/milestones`, filtered to the member over all time. That page lists
  every current member's, newest first, filtered by member, kind, and period, and opens
  on the last 90 days, for thanking people at a meeting or in a newsletter. Members open
  it too (#440): it comes from attendance they see already.
  [MemberMilestones](../lib/app/view_data/member_milestones.ex) loads them. Still not
  stored: South Fraser takes about 0.3 s on Fly (15,000 attended rows, 2026-10-23), once
  the page connects, and a stored copy would go stale whenever attendance, `joined_at`,
  or an away period changed.
- The `/me/card/…` Wallet downloads, `/me/tax-credit-letters/:id/pdf`, and `/wallet/…`
  stay: passes and files hold them.

### The year page

`/teams/:subdomain/me/activities?year=2025`
([MeActivitiesLive](../lib/web/live/me_activities_live.ex)), "Your activities in 2025"
under the breadcrumbs Your membership › Activities (#406). The title says "Your" because
the browser tab and the breadcrumbs show it alone, where a team admin also has the team's
Activities.

- **The year switch** runs from this year back to the year the member joined
  (`MemberRecords.years_on_team/2`).
- **Hours in the year** (#576), the main column: bars for primary, secondary, and other
  hours, then hours by month, stacked by incident, exercise, and event. Primary and
  secondary count as the letter does (`CountTaxCreditHours`), so they match it. Other is
  the time on activities with neither hours tag, shown only when the year has some.
- **That year's letter**, beside the hours, as Your membership shows it. For the current
  year it says the letter comes once a team admin makes it, after the year ends. A past
  year with no letter shows nothing. On a phone it comes first.
- **Where they went that year**, under the letter: the Dashboard's map with only the
  activities they attended. No map when none of them has a place.
- **The year in numbers**, over the table: total hours as the letter counts them,
  activities, and incidents, each with a sparkline by month and against the year before:
  the same days of last year for this year, the whole year before for a past one
  ([MemberYear](../lib/app/view_data/member_year.ex)). No streaks, calendar of days out,
  or comparison with teammates: the page tells a member about their year, not how they
  rank or what they missed.
- **Every attended activity**, newest first, with which hours it counts for. Coming
  sign-ups are not here: Next up and the team's Activities have them.

### The Dashboard for members

The team's Dashboard, `/teams/:subdomain`
([TeamDashboardLive](../lib/web/live/team_dashboard_live.ex)), opens to members too
(#406), read only, and is where a member lands after logging in.

- **Members see the team admin's page without its controls**: Next up, the team's next
  activity, with a maps link and how many signed up; Coming up, the team's next
  activities, each linked from its title; the team's year; and **For you to do**. The
  line under the team's name says when SAR Duty last refreshed, with Open in D4H.
- **Replies** (#444): a member replies to an activity they're invited to from Next up and
  Coming up, until it starts. A team admin replies as their own member row, found by
  email, on a team with member logins off too. See [Replies](#replies).
- **Take attendance** on Next up: team admins at any time, and members from 2 hours
  before the activity starts until 2 hours after it ends (#475,
  [taking-attendance.md](taking-attendance.md)).
- **Team admins also get** Needs attention and Refresh now, which goes while a refresh
  runs. Needs attention says when there's attendance to send: members take it on their
  own, so nothing else would tell them (#475,
  [taking-attendance.md](taking-attendance.md)).
  A team admin who is a member sees both For you to do and Needs attention, one above
  the other. A member's page doesn't work out Needs attention at all.
- **For you to do** comes from [MemberToDo](../lib/app/view_data/member_to_do.ex), pure:
  add your ID card to Wallet (on a team with ID cards on, until
  `MemberCard.in_wallet?/1`), each qualification expiring within 60 days (until it's
  renewed), and a new tax credit letter (from January to April, until the member
  downloads it, `downloaded_at`). Each leaves once done. With nothing to do, the card
  says so in one line.
- `"refresh"` is a team admin's event: the team pages' hook refuses it from a member
  (#440), and only a team admin's visit starts the catch-up sync.
- Links to team admin pages show only to team admins. The Current members stat links to
  Members for everyone (#440).

### Activities for members

The team's Activities, `/teams/:subdomain/activities`, and an activity's page open to
members too (#406), read only. Members see the same data as team admins, unless D4H
hides it from members or there is a real need (decided 2026-10-22: in a volunteer team,
hidden data makes people suspicious).

- **Which activities**: every activity D4H still has, incidents too, as D4H shows them
  to members. A team admin also sees one D4H has deleted, under a banner; a member gets
  a 404. D4H's `published` means locked, not visible, so it plays no part.
- **The list** is the team admin's: the same filters, columns, tags, hours, Draft, and
  default. Team admins also get Add activity and the Templates tab.
- **An activity's page** is the team admin's: under the title, the day and time and the
  counts, "6 signed up · 2 can't make it · 5 no reply" ("6 attended · 2 absent · 5 no
  reply" once it starts). The sidebar has Kind, the attendance total, Start with Add to
  calendar, Finish, Duration, tax credit hours, and the place with copy and the maps
  link; then Actions, with Open in D4H last. The main column has the tags, the map, the
  description, then tabs: Members (`/activities/:id`), Equipment (`/equipment`, with Add
  equipment at `/equipment/add`), Fields (`/fields`) when it has a custom field to show
  (#705), and History for team admins (`/history`). Take
  attendance is under the title for team admins, and for members from 2 hours before the
  start until 2 hours after the end; a member's Yet to arrive there shows names only.
  Team admins also get the History tab, which can hold contact details and addresses,
  the Actions, Add equipment, and links to each item's page. Member names link to member
  pages for everyone (#440). Members never see contact details.
- **Add to calendar** is `/teams/:subdomain/activities/:id/calendar`, an `.ics` file for
  anyone on the team (`require_team_access`). It replaced `/me/activities/:id/calendar`,
  with no redirect.

### Replies

A member replies to an activity they're invited to (#444): D4H has an attendance row for
them. The two buttons, I'll be there and Can't make it, sit under the counts on the
activity's page and in Next up, and small under the title in Coming up. After a reply
the member sees it, "Signed up" or "Can't make it", with Change to bring the buttons
back. Signed up adds Add to calendar, the activity's .ics file. Replies close when the
activity starts.

- **The reply** is a member change set ([change-sets.md](change-sets.md)) made by
  [ReplyToActivity](../lib/app/operation/reply_to_activity.ex), sent at once, and the
  copy updates with it. The control is
  [ReplyControl](../lib/web/components/reply_control.ex); the counts and the replier are
  in [Reply](../lib/web/components/reply.ex).
- **Who replies**: the member the user logs in as, or a team admin's own member row. A
  team admin viewing as a member sees that member's reply, and a tap saves nothing.
- **Not invited**: the counts alone, and nothing about invitations.
- **From a reminder's link** (`/replies/:token`,
  [ReplyLinkLive](../lib/web/live/reply_link_live.ex)): no login. The signed link
  ([Web.ReplyLinks](../lib/web/reply_links.ex)) is for one member and one activity and
  only replies, so its change set has no user. Opening it changes nothing, since some
  mail apps open every link. Each email button adds its answer (`?reply=yes` or `no`),
  and the page is a form with that answer selected and one Send reply (#488), a plain
  post to [ReplyLinkController](../lib/web/controllers/reply_link_controller.ex) so it
  works before the page connects. An answer that matches their reply shows the reply
  and Change instead. Its Add to calendar is `/replies/:token/calendar`, the same .ics
  with no login. It closes at the start, and always has "Open activity (log in)".
- **Invitation reminders** are the member's setting, not the login's: many members get
  email without ever logging in. On by default, a switch for each team in account settings
  ([AccountLive](../lib/web/live/account_live.ex)), and a
  reminder's "Turn off invitation reminders" link opens `/reminders/:token`
  ([InvitationRemindersLive](../lib/web/live/invitation_reminders_live.ex)), a page with
  one button that turns them back on too. A mail app's one-click unsubscribe posts to
  the same URL ([InvitationRemindersController](../lib/web/controllers/invitation_reminders_controller.ex)).
- **Add members** (#564,
  [ActivityAddMembersLive](../lib/web/live/activity_add_members_live.ex)): before the
  start, a team admin adds members by name or by group from
  `/teams/:subdomain/activities/:id/members/add`, an arrow link on the Members tab. They show as
  No reply, and adding emails nobody. A group leaves out members away on the activity's
  day, and the page names them; adding one by name includes them. A published activity
  says so in place of the link. D4H's own weekly briefing may still tell them.
- **Reminders** ([SendReminders](../lib/app/operation/send_reminders.ex)): before the
  start, a team admin opens Send reminders from the activity's Actions, a page at
  `/teams/:subdomain/activities/:id/reminders`
  ([ActivitySendRemindersLive](../lib/web/live/activity_send_reminders_live.ex), #608). It
  lists each member with no reply who can get an email, all checked, with the dates they
  were emailed before. Unchecking a member leaves them out. Then who gets none and why,
  a line each: replied already (a count of signed up and can't make it), turned off
  invitation reminders, or no email in D4H. Then the email itself, from the mailer's own
  HTML, and Send 3 emails. A message (optional, up to 300 characters, #609) adds the team
  admin's own words under the date and place; the preview shows it as they type, at a
  phone's width, so they see whether it pushes the buttons off the first screen. Each
  send starts with no message, so an old one never goes out again by mistake. Members who replied never get one. There is no limit per
  member: the team admin sees each member's past emails and decides (2026-10-26; #444
  had a cap of 2, a day apart). Each goes at once, from the team's name, with replies to
  the team admin ([ActivityMailer](../lib/app/mailer/activity_mailer.ex)). Its text sets
  no colour, so a mail app in dark mode keeps it readable. Each is a row in `reminders`:
  who, when, by whom, the message, and sent or failed. A No reply row's Replied cell reads "Reminded
  Oct 26", or "Reminder failed". Beside the Members heading, the last batch: "4 sent Oct
  26, 18:02 by Alex Chen · 2 replied since". The message's hint says members who
  replied don't get it, and links to Send an update.
- **Updates** ([SendActivityUpdate](../lib/app/operation/send_activity_update.ex), #609):
  before the start, a team admin opens Send an update from the activity's Actions,
  `/teams/:subdomain/activities/:id/updates`
  ([ActivitySendUpdateLive](../lib/web/live/activity_send_update_live.ex)), to tell
  everyone on the activity something, such as a new meeting place. The message is
  required, up to 300 characters. Every member with an email starts checked, in a table
  per reply (Signed up, Can't make it, No reply), each with select all. Each email ends
  with where the member stands, read when it goes: "You're signed up." or "You said you
  can't make it." with Change your reply, or the reply buttons for a member with no
  reply. A member with no reply who turned invitation reminders off gets no buttons,
  only Open activity, so it stays an update and not an invitation. Updates ignore that
  setting otherwise, and carry no unsubscribe. The preview shows one ending at a time.
  Earlier updates are listed at the top with their message, sender, and count. Each is
  a row in `activity_updates`. Asking only members with no reply is Send reminders,
  which the page links to.
- **Members**, under the map, lists everyone the activity invites
  ([ActivityMembers](../lib/app/view_data/activity_members.ex)): a stat switch of All,
  Signed up, Can't make it, and No reply (Attended, Absent, and No reply once it starts),
  each count a filter, `?view=signed-up` and so on. Then one table, by reply and then
  name: Name, Reply with its marker, Replied with New for the last 24 hours, and ID.
  Once it starts, Attendance, Start, Finish, and Duration replace Reply and Replied.
  Start shows a date only when it isn't the activity's day. Each part keeps the
  columns, even Reply or Attendance, which then repeats on every row (2026-10-25).
  Start, Finish, and Duration go when no row in the part attended, and Replied when
  no row in it replied or was reminded.

### View as member

A team admin opens a member's pages as the member sees them (#425), to check the data
and find pages that break. **View as member** on the member's page
(`POST /teams/:subdomain/members/:id/view-as`,
[ViewAsController](../lib/web/controllers/view_as_controller.ex)) puts the member's id in
the session and opens Your membership. It shows nothing new: team admins see every value
on these pages already, on the member's page and its tabs.

- `team_access!` in [Web.UserAuth](../lib/web/user_auth.ex) applies it. On pages members
  open, the team admin is that member and not a team admin, so the side navigation, the
  Dashboard, and the activity pages are the member's. Team admin pages stay the team
  admin's. The member is looked up through the URL's team, so another team ignores it.
- A banner on every team page names the member, with **Stop viewing**
  (`DELETE /teams/:subdomain/view-as`), which goes back to the member's page.
- It's read-only. On every page members open, only the page's `view_events` (filters,
  form checks) reach it, and anything else, such as saving contact details or a chore,
  says "You're viewing as …, so nothing is saved" (`UserAuth.view_as_refusal/1`) from
  the team pages' hook (#440). The save and delete buttons on Your membership's forms
  are greyed out too, so they don't look like they work. Wallet passes redirect back,
  and the letter downloads without leaving the member's to-do. Nothing reaches D4H and
  no code is sent. Replies, a component's own events, check `viewing_as` themselves.
- The account menu stays the team admin's, and each start is a `member_viewed_as` event in
  `/admin/events`, kept two years.
- Finding a broken page: `team_access!` gives Honeybadger the user, the member, and
  whether they are viewing as someone, so an error report on Your membership names the
  member. View as them to see the page break.

### Members for members

Members open the Members list, Milestones, and three tabs of a member's page (#440). They
see what they could work out from activities they open, plus role, ID, groups, and
qualifications. They don't see what comes from team admins' own tools: contact details,
away periods, check-ins, history, and ID cards.

- **The list**: the same columns, search, and Period, Group, and Tag filters. The
  Standing switch is Not retired, Not a person, and Retired, and its menu adds All. No
  Active, since Not retired minus Active would name who is away. No Attended or Details
  filter, and no Add member. The Member column's badge never says Away.
- **A member's page** is the team admin's minus controls: Attendance, Qualifications
  (with no Certificate, since D4H marks the documents RESTRICTED), and Groups as plain
  text. The sidebar is the ID and Milestones. The header has the photo and facts, a
  Retired or Not a person badge, never Away, and no View as member. Equipment, Standing,
  ID card, and History stay team admins'.
- **Their own page** opens Your membership: a member opening their own member page is
  sent there (`MemberPage.on_mount(:own_page, …)`), so every link to it works.
- **Email stays private**, with phone and address (decided 2026-10-24): no team needs it
  shown to every member. A directory members opt into can come later if people ask.

## Opening a page to members

How every page both roles open is built (#440). Members get the team admin's page minus
its controls, and the few values kept private. Decide each value, then scope it in one of
the places below, once.

**The test for each value.** Show it if members can rebuild it from pages they open, or
D4H shows it to them. Cut it if it exists only because a team admin wrote it down (away
periods, check-ins, history, the missing details list), or it is about how to reach
someone or their welfare. A value members can already see needs no guard.

1. **The page**: `access: :team` on the LiveView ([Web](../lib/web.ex)), and the route in
   the router test's list.
2. **Its events stay team admins'.** `:ensure_team_access` drops a member's event before
   the page's `handle_event`, unless the page lists it in `view_events`: the events
   that only change what the page shows, such as a filter form's `"change"`, or in
   `member_events`: the few actions members take too, such as a scan on Take attendance
   (#475). So `handle_event` has no `team_admin?` clauses. A member's own pages take
   every event from the member. Viewing as a member, every page members open takes only
   its `view_events`, and the rest say nothing is saved, so no page checks `viewing_as`
   itself. Team admin pages stay the team admin's. Events a component handles
   (`phx-target`), such as replies and search, go to the component, which checks for
   itself.
3. **Params**: the view model's `validate/2` takes `team_admin?` and drops what members
   can't set before it casts ([MemberFilterViewModel](../lib/app/view_model/member_filter_view_model.ex)).
   The list, its counts, and the form all read the result, so nothing after checks again.
4. **Parts of the page**: the page decides, and a part doesn't ask. Something only team
   admins see is its own component or column, shown with `:if={@team_admin?}`. A shared
   component with such a part takes `team_admin?` with `default: false`, so a page that
   forgets shows the member's view. [MemberPage](../lib/web/components/member_page.ex)
   takes it once for the header, tabs, and sidebar of every member tab.
5. **One home for a rule pages share**: another member's standing as the viewer sees it
   is `MemberAwayPeriod.visible_standing/2`, which the header and search both use.

Each guard gets a test: an element id that must be absent (`member-phone`), a member's
URL params, and an event from a member that changes nothing.
[Web.MemberPagesTest](../test/web/member_pages_test.exs) opens every page members reach,
as a member and viewing as one. It fails on a link they can't open, a control whose
event a member's page refuses, or a form whose change view as refuses. A new member page
goes in its list.

### What must stay true

- **A member's own page shows only the person logged in**, or the member a team admin
  views as.
  `current_member` comes from the login, in `on_mount(:ensure_team_access, …)`, and
  `member` in the `require_team_member` plug ([Web.UserAuth](../lib/web/user_auth.ex)). No
  member page or download takes a member id from the URL. A letter is found by its id and
  the member's id together
  ([TaxCreditLetter.find_for_member!/2](../lib/app/model/tax_credit_letter.ex)).
- **Admins get no pass without asking.** A SAR Duty admin reaches every team page, but
  another person's member pages only through View as member, which is read-only.
- **Who logs in as a member is one query**:
  [Member.get_logins/2](../lib/app/model/member.ex). The team has member logins on, and
  the member is current, isn't retired, and isn't retiring; Not a person logs in too.
  Two such members on one team with the same email match neither, since SAR Duty can't
  tell whose card to show. `Accounts.may_log_in?/2` uses it, so emailed and texted codes
  both work.
- **Every request checks again.** Turning member logins off, or the refresh seeing a
  member leave, ends access on the next page. Getting a card checks the login again, in
  case the page was open when access ended.
- **Every team page is in one `live_session`** (#406), with one hook,
  `:ensure_team_access`. `current_team` is always the URL's team. A page is for team
  admins unless its LiveView says `access: :team` (members too) or `access: :member`
  (members only, their own pages); see [Web](../lib/web.ex). The router test lists every
  route a member reaches, and a sweep checks every other team route 404s for one.
- **Members don't issue cards.** Issuing, replacing, and cancelling stay with team admins,
  on the member's ID card tab, and only on a team a SAR Duty admin turned ID cards on for
  ([member-cards.md](member-cards.md)).
- **Member visits don't count as team use.** `RecordUserSeen` isn't called from member
  pages, so `/admin` still shows which teams' admins use SAR Duty.
- **Hours match the letter.** The page counts with `CountTaxCreditHours`, as the letter
  and the letter list do, so a member sees the number their letter will say. Their
  records come from [MemberRecords](../lib/app/view_data/member_records.ex), which filters
  by the member and their team.
- **A member's own edits go straight to D4H.** Saving their details is a change set of
  source `:member`, proposed and applied in one step by
  [SaveOwnDetails](../lib/app/operation/save_own_details.ex), with the member's user on
  it. D4H records SAR Duty's key as the editor, so the change set is the record of who
  asked. Only the fields that changed go, with D4H's old values.
- **Emergency contacts are copied** from D4H's member list, like the phone and address
  (#423). The details page shows the copy, and saving updates it. A member sees only
  their own; team admins see every member's on the member's page, with Call and Text. The
  change set row keeps the old and new contact, as every row keeps what it changed, but
  history says only "Emergency contact changed". SAR Duty Records serves them as D4H
  does. A change made in D4H in the 10 minutes before a member saves is overwritten.
- **A new mobile number needs a code first.** Text login uses it, so
  [ChangeOwnPhone](../lib/app/operation/change_own_phone.ex) texts a code to the new
  number, a `"confirm"` user token that lives and dies like a login code, with the login
  rate limits. Only a matching code sends the change to D4H. The member's email then gets
  a notice, in case someone else made the change.
