# Navigation

How a page shows where it is (#312, #406). Every page is in one area, and the layout draws
the same three things for each: the top bar names the area, the side navigation lists the
area's pages, and the account menu holds your login. [Web.Navigation](../lib/web/navigation.ex)
decides all of it from the page's path and assigns. It is pure, and
[its test](../test/web/navigation_test.exs) runs without a database.

Narrow pages (`/styles/layout`) keep the top bar and drop the side navigation; their Menu
still lists the area's pages.

## Areas

- **A team's space**, `/teams/:subdomain/…`. One per team, for everyone on it: team
  admins and members open the same URLs, and a person's role decides which pages and
  controls they see (#406). The team is the URL's, which the team pages' hook assigns as
  `current_team`, with `team_admin?` and `current_member`. There is no separate member
  area.
- **An organization's space**, `/orgs/:slug/…` (#512), for its organization admins and
  SAR Duty admins. The organization is the URL's, which its pages' hook assigns as
  `current_organization`. Its side navigation is Teams, then Organization settings, whose
  pages are tabs: General, Organization admins, and Hours tags. The bar names the
  organization, and the phone bar its short name. It has no search, since search reads a
  team's tables.
- **SAR Duty admin**, `/admin/…`, for SAR Duty admins: Teams and Organizations, then
  Admins, Events, and MCP calls. The Style guide is in the team switcher. Each team has
  its own page, `/admin/teams/:id`, under Teams, with its refresh, team admins and login
  grants, and its ID cards and MCP switches (#513). Every admin page is a 404 for anyone else.
- **The footer** (Verify an ID card, Terms, Privacy) is only on the public pages: home,
  terms, and privacy. In an area its links are noise. In dev, app pages keep a line with
  the dashboard and the mailbox.
- **Account settings**, `/account`: one page, so no side navigation. It is about the login,
  the same on every team.

Public pages and logging in are in no area. Their bar has the account menu and no area
name.

The style guide, `/styles`, is in no area either, so its bar is the home page's. Its own
side navigation lists its 3 groups, then the open group's pages, and on a phone it goes
behind the bar's Menu, logged in or not.

## The side navigation

Sections, split by a divider, with no headings. A section with nothing the person can see
is left out, and so is its divider.

| Section | Links                                                    | Who         |
| ------- | -------------------------------------------------------- | ----------- |
| 1       | Dashboard, Whiteboard                                    | everyone    |
| 2       | Activities, Take attendance                              | everyone    |
| 2       | Templates                                                | team admins |
| 3       | Members, Milestones                                      | everyone    |
| 3       | Groups, Qualifications, Endorsements, Tax credit letters | team admins |
| 4       | Equipment                                                | team admins |
| 4       | Chores                                                   | everyone    |
| 5       | Reports                                                  | team admins |
| 6       | Team settings                                            | team admins |
| 7       | Your membership                                          | members     |

- A team admin who is a member sees all seven. A SAR Duty admin who opened a team from
  Admin and is not a member there sees 1 to 6. A member sees Dashboard and Whiteboard,
  Activities and Take attendance, Members and Milestones, Chores, and Your membership,
  each in its own section (#440, #645).
- **Whiteboard follows Dashboard** while the team has D4H's whiteboard on (#515). The
  Dashboard shows a line or 2 of its notes; the page has them all, and team admins post
  from it.
- **Take attendance is always there**, after Activities, for members and team admins
  (#475). Not only while an activity is on: links that come and go with the clock make
  the menu harder to learn. It opens `/teams/:subdomain/take-attendance` in the app
  layout, like every page here; the scanner a row opens is a narrow page.
- **Templates is a link of its own**, after Activities, so a team admin finds it without
  opening Activities first. Proposed changes sat beside it until the MCP became read-only
  (#627).
- **No counts** (2026-10-31). Chores and Certificates each counted what waited for a team
  admin in an amber tag, and lit an amber dot on the phone's Menu button. Both counted a
  team admin's own, which another team admin should accept, so a team admin whose own
  waited saw a count they shouldn't act on. Chores lost its count first (#698), then
  Certificates. What waits is on the Dashboard's Needs attention, which leaves out the
  reader's own unless no other team admin can accept it.
- **Team settings is one link** to `/teams/:subdomain/settings`. Its pages are tabs under
  the title Team settings ([TeamSettingsTabs](../lib/web/components/team_settings_tabs.ex)),
  one topic each (2026-10-27, #514): General (the team and its key), Team admins, and
  Features; Members (the Retiring group and the attendance check); Tax credit letters
  (address and signer) and Hours tags; Places and Chore categories; then MCP tokens.
  Features comes before the tabs it decides on (2026-10-28). General held the letters and the attendance check until then, one long form
  with four topics.
- **Features is where a team turns things on** (2026-10-28): member logins, with chores
  and certificates under them, and the whiteboard, one switch each that saves when
  flipped. ID cards show as on or off; SAR Duty turns them on when a team asks. MCP isn't
  offered: it shows only once a SAR Duty admin turns it on. A feature's own settings
  are a tab that shows only while it is on: Chore categories, MCP tokens. A new feature a
  team can go without gets a switch here, off on a new team.
- **Tax credit letters sits with the people pages**, after Endorsements (2026-10-22): a
  letter is about members, and a section of one link made the menu look like a table.
- **Chores shares Equipment's section** for team admins (2026-10-22): most chores are
  equipment upkeep, and a section of one link looked lost. Members get it in a section of
  its own (#645). Chores shows only with member logins and chores on (#463).
- **Milestones sits right after Members** (2026-10-23): every current member's
  milestones. It's about members themselves, as Members is; Groups, Qualifications, and
  Endorsements set up what members hold. Members open both (#440).
- Later pages already have homes: Checks in Equipment's section, for everyone, and
  Documents and a team ID cards page after Tax credit letters.

## Where a feature goes

Decided 2026-10-27 (#645). A feature members use had two homes: a team admin's page and a
section on Your membership. A team admin who is also a member looked for Log a chore under
Chores, and it was on Your membership. Every feature on the roadmap would have added
another pair. So a feature gets one home, picked by these rules in order.

1. **About one activity, item, or member? A part of that page.** It adds no link to the
   side navigation. Travel and home safe (#261) go on the activity, in place of its
   Mileage report. Off call (#646) goes in the header of Your membership and in a filter
   on Members. A check (#407) runs from the item's page, which its sticker opens.
2. **A list people open on their own? One link and one URL, for everyone.** Members open
   it on Yours, their own rows, with their button. Team admins also get the team's views.
   Chores is the first, `/teams/:subdomain/chores`; Checks (#407) is next. No copy of it
   under `/me`.
3. **About you? Your membership.** Who you are, your year, what you hold, your letters,
   and how to reach you. A feature's list never gets a section there, at most a line that
   links to the feature's Yours view, as Chores has.
4. **Needs you now? For you to do, on the Dashboard.** A check due, a declined chore, a
   letter to download. Only an urgent state gets a strip on every page, such as a trip
   home in progress (#261). Off call lasts days, so it stays on the Dashboard and in your
   header.
5. **No wrong door.** Where someone looks for an action, it is there. A team admin's queue
   has the member's button too: Log a chore on Chores, Add a certificate on Certificates.
   A team admin on their own member page gets the team admin's view, with a banner that
   sends them to Your membership.

Admin-only links get no mark in the side navigation. With one home per feature, a page
shows your part beside the team's, so there is nothing to mark. The options weighed, with
mockups, are on #645.

## The top bar

- **The logo** always goes to the home page, logged in or not, so the public site is
  never out of reach. Logged in on a page outside every area (home, terms, privacy), the
  bar looks as it does elsewhere: it names the team logging in lands on, else your member
  team, else your first organization, else SAR Duty admin (`Navigation.outside_area/4`),
  with the switcher on it. The
  page is in no area, so the switcher marks nothing and the name always opens it.
- **After the logo, the area's name**: the team's, the organization's, SAR Duty admin, or
  Account settings.
- **The team switcher** sits on the name when you can go somewhere else, at every width.
  Its menu lists Your teams, each team where you are a team admin or a member, A to Z,
  one row per team (`Navigation.switch_rows/5`), then Your organizations, each one you are
  an organization admin of, with a building icon (#512). SAR Duty admins reach the other
  organizations from Admin › Organizations. For SAR Duty admins, SAR Duty admin comes
  last, below a divider and with a shield, so it never reads as one more team
  (2026-10-23). The team you're on is marked, and each row goes to the team's Dashboard; a
  team opened from Admin › Teams that isn't yours marks nothing. With one place to be,
  the name is plain text.
- **Your avatar, top right** at every width: your initials in a circle, from the name of
  the member you log in as, or else your email (`Navigation.person/3`). It opens your name
  and email, Account settings, and Log out. It is the same on every team, and Your
  membership is not in it.

## Rules

- A side navigation link is current on its page and every page under it. An area's
  first page (Dashboard, Teams) is current only on itself.
- Breadcrumbs start at the section, never the team, and a section's own page has none.
  The section is the side navigation link that is current. A member's certificate form
  is under `/certificates`, which members have no link to, so for them it sits under
  Your membership, and that link is current there; a team admin's sits under
  Certificates (#645). Audited 2026-10-28: Whiteboard, Templates, Endorsements, and Tax
  credit letters are sections of their own, so their pages have no trail.
  A record's tabs sit under its title, above both columns. An activity's and an
  equipment item's sit in the main column, under what the record is.
- Below 1024px the side navigation hides (#471). The Menu button moves to the left of the
  bar, the logo sits over the area's name in the middle, and your avatar stays on the
  right with the same account menu. The switcher stays on the name, with a chevron, and
  opens its own panel under the bar (2026-10-23: #472 had moved it into Menu, where
  people on two teams didn't find it). Menu holds the side navigation's sections with
  their dividers; with none, there is no Menu button. The bar's menus share one
  `details` name, so opening one closes the others.
- Search (#471) is in the bar but commented out until it has a page: a field before the
  avatar on a desktop, an icon below 1024px.

## Adding a page

A new page is a route and a LiveView with `use Web, :live_view_app_layout`, or the narrow
layout for a task done with a phone or iPad in hand; see `/styles/layout`. A team page is
for team admins unless it says `access: :team` or `access: :member`; opening one to
members has its own steps ([members.md](members.md#opening-a-page-to-members)). If it
belongs in the side navigation, add a line to `Web.Navigation`. A page under an existing link needs nothing: the link is current on it.
The guide shows the parts at `/styles/top-bar` and `/styles/side-nav`.
