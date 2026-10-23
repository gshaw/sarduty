# Navigation

How a page shows where it is (#312, #406). Every page is in one area, and the layout draws
the same three things for each: the top bar names the area, the side navigation lists the
area's pages, and the account menu holds your login. [Web.Navigation](../lib/web/navigation.ex)
decides all of it from the page's path and assigns. It is pure, and
[its test](../test/web/navigation_test.exs) runs without a database.

## Areas

- **A team's space**, `/teams/:subdomain/…`. One per team, for everyone on it: team
  admins and members open the same URLs, and a person's role decides which pages and
  controls they see (#406). The team is the URL's, which the team pages' hook assigns as
  `current_team`, with `team_admin?` and `current_member`. There is no separate member
  area.
- **SAR Duty admin**, `/admin/…`, for SAR Duty admins: Teams, Organizations, and ID cards,
  then Admins, Events, and MCP, then the Style guide.
- **The footer** (Verify an ID card, Terms, Privacy) is only on the public pages: home,
  terms, and privacy. In an area its links are noise. In dev, app pages keep a line with
  the dashboard and the mailbox.
- **Account settings**, `/account`: one page, so no side navigation. It is about the login,
  the same on every team.

Public pages, logging in, and the door's attendance link are in no area. Their bar has
the account menu and no area name.

## The side navigation

Sections, split by a divider, with no headings. A section with nothing the person can see
is left out, and so is its divider.

| Section | Links                                                                         | Who         |
| ------- | ----------------------------------------------------------------------------- | ----------- |
| 1       | Dashboard                                                                     | everyone    |
| 2       | Activities                                                                    | everyone    |
| 2       | Templates, Proposed changes                                                   | team admins |
| 3       | Members, Milestones, Groups, Qualifications, Endorsements, Tax credit letters | team admins |
| 4       | Equipment                                                                     | team admins |
| 5       | Team settings                                                                 | team admins |
| 6       | Your membership                                                               | members     |

- A team admin who is a member sees all six. A SAR Duty admin who opened a team from
  Admin and is not a member there sees 1 to 5. A member sees Dashboard, Activities, and
  Your membership, each in its own section.
- **Templates and Proposed changes are links of their own**, after Activities, so a team
  admin finds them without opening Activities first. Proposed changes shows only when the
  team has MCP on, or something waits. It counts the AI agent change sets that wait for a
  team admin in an amber tag (`ChangeSet.count_waiting/1`, assigned by the team pages'
  hook), and on a phone the Menu button gets an amber dot while any link has a count.
- **Team settings is one link** to `/teams/:subdomain/settings`. Its pages are tabs under
  the title Team settings ([TeamSettingsTabs](../lib/web/components/team_settings_tabs.ex)):
  General, Team admins, Member logins, Hours tags, and MCP tokens once a SAR Duty admin
  turns MCP on. Until then, General says how to get it. The URLs did not change.
- **Tax credit letters sits with the people pages**, after Endorsements (2026-10-22): a
  letter is about members, and a section of one link made the menu look like a table.
- **Milestones sits right after Members** (2026-10-23): every current member's
  milestones, for team admins. It's about members themselves, as Members is; Groups,
  Qualifications, and Endorsements set up what members hold. Members see only their own, on Your membership, until
  we decide how members see other members' pages.
- Later pages already have homes: Checklists in Equipment's section, and Documents and a
  team ID cards page after Tax credit letters.

## The top bar

- **The logo** always goes to the home page, logged in or not, so the public site is
  never out of reach. Logged in on a page outside every area (home, terms, privacy), the
  bar looks as it does elsewhere: it names the team logging in lands on, else your member
  team, else SAR Duty admin (`Navigation.outside_area/3`), with the switcher on it. The
  page is in no area, so the switcher marks nothing and the name always opens it.
- **After the logo, the area's name**: the team's, SAR Duty admin, or Account settings.
- **The team switcher** sits on the name when you can go somewhere else. Its menu, headed
  Switch team, lists SAR Duty admin first for SAR Duty admins, then each team where you
  are a team admin or a member, A to Z, one row per team (`Navigation.switch_rows/4`). The
  team you're on is marked, and each row goes to the team's Dashboard; a team opened from Admin › Teams that isn't yours marks
  nothing. With one place to be, the name is plain text.
- **Your avatar, top right**: your initials in a circle, from the name of the member you
  log in as, or else your email (`Navigation.person/3`). It opens your name and email,
  Account settings, and Log out. It is the same on every team, and Your membership is not
  in it.

## Rules

- A side navigation link is current on its page and every page under it. An area's
  first page (Dashboard, Teams) is current only on itself.
- Breadcrumbs start at the section, never the team, and a section's own page has none.
  A record's tabs sit under its title, above both columns.
- Below 1024px the side navigation and the account menu hide. The Menu button holds
  Switch team and its rows (only with somewhere else to go), a divider, the side
  navigation's sections with their dividers, a divider, then your avatar with your name
  and email, Account settings, and Log out.

## Adding a page

A new page is a route and a LiveView with `use Web, :live_view_app_layout`. A team page is
for team admins unless it says `access: :team` or `access: :member`
([members.md](members.md)). If it belongs in the side navigation, add a line to
`Web.Navigation`. A page under an existing link needs nothing: the link is current on it.
The guide shows the parts at `/styles/top-bar` and `/styles/side-nav`.
