# Navigation

How a page shows where it is (#312). Every page is in one area, and the layout draws the
same three things for each: the top bar names the area, the side navigation lists the
area's pages, and the account menu switches areas.
[Web.Navigation](../lib/web/navigation.ex) decides all three from the page's path and
assigns. It is pure, and [its test](../test/web/navigation_test.exs) runs without a
database.

## Areas

- **Team area**, `/teams/:subdomain/…`, for the team's admins. The team is the URL's,
  which the team pages' hook assigns as `current_team`. The side navigation: Dashboard;
  Activities, Templates, and Proposed changes; Members, Qualifications, and Groups;
  Equipment; Tax credit letters; and Settings (General, ID cards, Team admins, Member
  logins, MCP tokens).
- **Member area**, `/teams/:subdomain/me/…`, a member's own pages. The team is the
  member's, from `member.team`: on these pages `current_team` is the team the user last
  managed, not the URL's. The side navigation: Overview, ID card, Qualifications,
  Activities, Hours, Tax credit letters, and Contact details. ID card shows once the team
  has ID cards.
- **Admin**, `/admin/…`, for SAR Duty admins: Teams, Organizations, and ID cards, then
  Admins, Events, and MCP.
- **Your settings**, `/account`: one page, so no side navigation.

Public pages, logging in, and the door's attendance link are in no area. Their bar has
the account menu and no area name.

## The account menu

- Admin, for SAR Duty admins.
- Each of your teams, A to Z, under its name: Team area if you're one of its team admins
  (`Team.get_managed_by/2`), and Member area if it lets you log in as a member
  (`Member.get_logins/2`). An admin's menu lists only their own teams; Admin → Teams
  reaches the rest, and nothing marks a team they open that way.
- Your settings, then Log out.

## Rules

- A side navigation link is current on its page and every page under it. An area's
  first page (Dashboard, General, Overview, Teams) is current only on itself.
- A group of two or more links has a heading in small capitals (`.caps`), the style the
  menus use for team names. A group of one has none.
- Proposed changes counts the AI agent change sets that wait for a team admin, in an
  amber tag (`ChangeSet.count_waiting/1`, assigned by the team pages' hook). It shows
  only when the team has MCP on, or something waits.
- ID cards and MCP tokens show under Settings once a SAR Duty admin turns them on. Until
  then, General says how to get them.
- Breadcrumbs start at the section, never the team, and a section's own page has none.
  A record's tabs sit under its title, above both columns.
- The bar says Team area or Member area after the team's name, as the account menu does.
- Below 1024px the side navigation hides. The Menu button holds the area's pages, then
  the account menu's list. The bar's label stays beside the logo on one line when it fits;
  a long name moves the area, kept whole, to a second line.

## Adding a page

A new page in an area is a route and a LiveView with `use Web, :live_view_app_layout`.
If it belongs in the side navigation, add a line to `Web.Navigation`. A page under an
existing link needs nothing: the link is current on it. The guide shows the parts at
`/styles/top-bar` and `/styles/side-nav`.
