# URLs

How paths are named, and which ones can never move. Issue #153 set these rules when
team pages moved under `/teams/`. [test/web/router_test.exs](../test/web/router_test.exs)
enforces the top-level list and the held URLs.

## Rules

- **Plural kebab-case nouns**: `/members`, `/tax-credit-letters`.
- **Local ids, never D4H ids**: `/members/42`. D4H ids stay in `d4h_*_id` columns.
- **Team pages live under `/teams/:subdomain`**, including the team's settings
  (`/teams/:subdomain/settings`, `/settings/managers`). The URL names
  the team a page acts on; there is no hidden "current team" for a page to change.
- **One URL per thing, for everyone on the team** (#406). A team admin and a member open
  the same `/teams/:subdomain/…` page; their role decides what it shows.
- **A member's own page is `/teams/:subdomain/me`**, Your membership, with the year page
  (`/me/activities?year=`), Contact details (`/me/details`), their photo (`/me/image`),
  and their downloads under it (#156, #406). Add to calendar is the activity's own,
  `/teams/:subdomain/activities/:id/calendar`, for anyone on the team. It names the team; the member is always the
  person logged in, or the member a team admin views as (#425). The old `/me/card`, `/me/qualifications`, `/me/hours`,
  `/me/milestones`, and `/me/tax-credit-letters` pages are gone with no redirects. See
  [members.md](members.md).
- **Organizations are `/orgs/:slug`** on both sites. On the app it is the organization's
  space (#512): `/orgs/:slug` (Teams), `/orgs/:slug/teams/new` (Add a team),
  `/orgs/:slug/teams/:subdomain`, `/orgs/:slug/settings`, `/settings/admins`, and
  `/settings/hours-tags`. A team can't have the subdomain `new`, which Add a team would
  hide; the Team changeset refuses it. `/admin/orgs/:id` went with no redirect. The verify site's
  `/orgs/:slug` is matched by host first, so the two never meet.
- **Nothing fixed directly under `/teams/` or `/orgs/`.** It would block a team or an
  organization with that name. That's why sign-up is `/signup`, not `/teams/new`.
- **Top-level paths are a short list**: `teams`, `orgs`, `admin`, `account`, `signup`,
  `login`, `logout`, `s`, `attendance`, `replies`, `reminders`, `wallet`, `styles`,
  `terms`, `privacy`, `maps`, and `dev` in development. A new one is added to the router
  test on purpose.
- **Anything printed or texted goes through `/s/` or the verify site**, so it stays short
  and never depends on a team page's path.
- **Build paths one way**: `~p"/teams/#{team}/members"`. `App.Model.Team` derives
  `Phoenix.Param` on `subdomain`, and `App.Model.Organization` on `slug`, so a future move
  is one router change and a grep.

## Held outside the app

Devices, Google, Apple, and shared links hold these. They don't move.

- `/wallet/v1/…`: Apple's web service path, in every issued pass.
- `/teams/:subdomain/me/card/apple-wallet`, `/me/card/google-wallet`, and
  `/me/tax-credit-letters/:id/pdf`: a member's downloads, kept so saved links keep
  working.
- `/wallet/google`: Google Wallet's save and delete callbacks, set on the pass class.
- `/s/:code` and `/attendance/:token`: shared attendance links.
- `/replies/:token` and `/reminders/:token`: a reminder email's links, to reply and to
  turn reminders off (#444). Mail apps post to `/reminders/:token` for one-click
  unsubscribe.
- `/teams/:subdomain/logo`: Google Wallet objects fetch it.
- `/teams/:subdomain/mcp`: agents' MCP configs hold it ([mcp.md](mcp.md)).
- On the verify site: `/:code` (the QR code), `/:code/photo`, `/:code/banner` (the Google
  Wallet banner), `/orgs/:slug`, and `/letters/:ref` (the QR code on every tax credit
  letter since #207).

Card images always use SAR Duty's verify host, even for an organization with its own,
since Google Wallet objects hold the banner URL.
