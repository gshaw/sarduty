# Members

The members list and a member's page, for team admins, and member logins, for members.

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
- **Standing** filters by [standing](#standing): Current (the default: everyone but the
  retired), Active, Away, Not a person, Retired, or All. It replaced Status, and old
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

No column chooser. A column shows only when it says something: Standing when some
current member is not active (or the filter goes past Current), Retired when the
Standing filter can show retired members, Missing with Details: Missing. ID hides on narrow screens.

## Standing

A member's **standing** says whether the team expects them to show up now (#366):
**Active**, **Away** for a dated period such as leave, **Not a person**, or **Retired**.
Decided 2026-10-18; the issue has the reasons. Retired was added 2026-10-19.

- **SAR Duty owns it.** Nothing about it goes to D4H. Teams on D4H and on SAR Duty
  Records work the same.
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
  an away period. **Active** is the absence of the others and is never stored.
- The member's **Standing** tab lists away periods, past ones too, with a form to add one
  and buttons to end one today or delete it. Any team admin can. The sidebar on every
  member tab shows the standing. Each change goes in the member's history, from
  `member_standing_changes`, which keeps the reason and dates.
- Members do not see their standing, and the reason is `redact: true`.
- **Check-ins** are on the same tab: a team admin records the day they reached a member
  and what they heard ([MemberCheckIn](../lib/app/model/member_check_in.ex)). It
  restarts the member's attendance clock and changes nothing else: not standing, not
  groups, nothing in D4H. If the call turns up leave, the admin adds an away period too.
  Any team admin can delete one recorded by mistake, and the clock goes back without it.
  Members do not see check-ins, and the note is `redact: true`.

Nothing leaves a group or a list for standing unless a rule written on its page says so.
These stay as they were, since a bot cannot attend or be invited, and skip members
marked not a person with no rule: invites (`InviteGroups`), the home page's counts and
charts, the missing details filter, and the attendance list at the door.

## The attendance check

Needs attention lists members who have not attended in a while, so someone can check in
with them (#247, #366). It is three choices on **Settings → General**, decided
2026-10-18: no settings page of its own and no live summary.

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
  qualification, soonest expiry first, then Does not expire, then Expired (muted). One
  that expires within 60 days, the app's one expiring window
  (`BuildGroupRulePreview.expiring_days/0`), gets a warning tag with its days left ("30
  days"), as a group's expiring members do. No banner says it again (decided
  2026-10-21): the row is first in the table, and the overview's For you to do already
  says what to do. The words are
  [Web.QualificationText](../lib/web/qualification_text.ex), so every page says the same
  thing.
- **No groups** (decided 2026-10-20). #308 asked for groups by expiry. On South Fraser's
  data, 11 of 84 members had anything expiring within 60 days, never more than 1, and
  most groups held 1 or 2 rows under their own heading. A tag finds the one that matters.
  `<.table groups={…}>` stays for lists where each group holds several rows.
- **One row per qualification**, from its latest award: when it expires (or expired) and
  the year it was first held. Team admins also get an Earlier awards column, with Remove
  on a team on SAR Duty Records. The admin's tab lost its Start column.
- **No component of their own** (decided 2026-10-20). Pages pick their columns from one
  set of rows, and the table does the rest. A two-line list wasted space.
- **Activities** are a table too: day, title linked to the activity in D4H
  (`<.d4h_activity_link>`), kind, and time there, newest first. No groups by month
  (decided 2026-10-20): a member attends a median of 19 a year, so a month heading sat
  over about 2 rows, and the date already says the month. Not by kind either, since every
  row shows its kind. A team on SAR Duty Records gets no links: a member cannot
  open its activities.
- **A team admin's Attendance tab keeps its table.** It searches, sorts, filters by hours
  and activity tag, and pages by 50, and links to SAR Duty's own activity page. Its years
  come from `MemberRecords.years/2`, as the member's own page lists them.

## Member logins

A team admin turns on member logins in **Settings → Member logins**, in the team area. Then every
current member of the team can log in with the email or mobile number D4H has for them,
and land on their own pages, the member area (#156, #389). Its side navigation has 7
pages, each its own LiveView under `/teams/:subdomain/me`:

| Page               | Path                     | What it holds                                          |
| ------------------ | ------------------------ | ------------------------------------------------------ |
| Overview           | `/me`                    | The member's year at a glance                          |
| ID card            | `/me/card`               | The card, the Wallet buttons, and the verify link      |
| Qualifications     | `/me/qualifications`     | Soonest expiry first, with expiring ones tagged        |
| Activities         | `/me/activities?year=`   | Signed up for, then the year's activities              |
| Hours              | `/me/hours?year=`        | Primary and secondary hours for the year               |
| Tax credit letters | `/me/tax-credit-letters` | Every year's letter as a PDF                           |
| Contact details    | `/me/details`            | Mobile number, mailing address, and emergency contacts |

ID card shows in the side navigation once a SAR Duty admin turns ID cards on for the
team. Contact details took in the old Mobile number page (`/me/mobile`, gone with no
redirect, decided 2026-10-20). Members don't change their email: teams keep it
consistent, and team admins change it in D4H. Logins are designed in issue #156, and
the pages in issue #389.

### The overview

The overview shows a member's year at a glance, as the team home does for team admins,
with the same parts (#389, closing #340): the name with "Member since" and when SAR
Duty last refreshed; **Next up**, the next activity they signed up for, with Add to
calendar (an `.ics` file from `/me/activities/:id/calendar`, only for their own sign-ups)
and a maps link; four stats (hours, activities, and incidents this year, and current
qualifications with the next to expire); **Where your hours went**, hours by kind this
year; **Where you went**, the team home's map of their last 12 months; and **Lately**,
their last 3 activities. The numbers come from
[MemberOverview](../lib/app/view_data/member_overview.ex), pure.

- **No calendar and no comparisons** (decided 2026-10-20). The median member attends
  about 10 activities a year, so a year calendar would be mostly empty, and "fewer than
  last year" discourages.
- **Hours here count every attended activity**, tagged or not, as hours by kind does. The
  Hours page and the tax credit letter count only tagged ones, and the overview says so
  with a link there. The Hours page shows the same bars for its year.
- With no activities, each chart is one line, not an empty chart.
- **Milestones** sit beside Lately: the latest 3, with All milestones to
  `/me/milestones` when there are more. Hours (100, 250, 500, 1,000, then every 1,000),
  years on the team (1, 5, 10, then every 5), and incidents (the first, 10, 25, 50, 100,
  then every 100), each dated by the day it was reached:
  [Milestones](../lib/app/view_data/milestones.ex), pure. They're worked out when the
  page loads, from `Attendance.attended/2`, `joined_at`, and away periods, so past ones
  show on day one and nothing is stored. Years leave out the days away: teams reopen a
  rejoining member's D4H record, and a team admin adds the gap as an away period. Hours count every attended activity, not only tagged ones. A
  plain dated list: no badges, graphics, or levels (decided 2026-10-20). The milestones
  page is not in the side navigation; Overview leads to it.
- **For you to do** sits under Next up, from
  [MemberToDo](../lib/app/view_data/member_to_do.ex), pure: add your ID card to Wallet
  (until `MemberCard.in_wallet?/1`), each qualification expiring within 60 days (until
  it's renewed), and a new tax credit letter (until the member downloads it,
  `downloaded_at`). Each leaves once done; the layout stays the same. With nothing to do,
  the card says so in one line.

### What must stay true

- **A member page shows only the person logged in.** `member` comes from the login, in
  `on_mount(:ensure_team_member, …)` and the `require_team_member` plug
  ([Web.UserAuth](../lib/web/user_auth.ex)). No member page or download takes a member id
  from the URL. A letter is found by its id and the member's id together
  ([TaxCreditLetter.find_for_member!/2](../lib/app/model/tax_credit_letter.ex)).
- **Admins get no pass.** A SAR Duty admin reaches every team page, but not another
  person's member page.
- **Who logs in as a member is one query**:
  [Member.get_logins/2](../lib/app/model/member.ex). The team has member logins on, and
  the member is current, isn't retired, and isn't marked not a person. Two such members on
  one team with the same email match neither, since SAR Duty can't tell whose card to
  show. `Accounts.may_log_in?/2` uses it, so emailed and texted codes both work.
- **Every request checks again.** Turning member logins off, or the refresh seeing a
  member leave, ends access on the next page. Getting a card checks the login again, in
  case the page was open when access ended.
- **Member pages are outside the team pages' `live_session`.** They set `member`, which
  puts them in the member area ([navigation.md](navigation.md)), and never set
  `current_team`. A team admin is a member too, and switches to their member area from
  the account menu.
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
- **Emergency contacts are never copied.** The details page reads them from D4H each time
  it opens. The change set row keeps the old and new contact, as every row keeps what it
  changed. SAR Duty Records has no emergency contacts, so its members change only their
  address.
- **A new mobile number needs a code first.** Text login uses it, so
  [ChangeOwnPhone](../lib/app/operation/change_own_phone.ex) texts a code to the new
  number, a `"confirm"` user token that lives and dies like a login code, with the login
  rate limits. Only a matching code sends the change to D4H. The member's email then gets
  a notice, in case someone else made the change.
