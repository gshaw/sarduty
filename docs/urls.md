# URLs

How paths are named, and which ones can never move. Issue #153 set these rules when
team pages moved under `/teams/`. [test/web/router_test.exs](../test/web/router_test.exs)
enforces the top-level list and the held URLs.

## Rules

- **Plural kebab-case nouns**: `/members`, `/tax-credit-letters`.
- **Local ids, never D4H ids**: `/members/42`. D4H ids stay in `d4h_*_id` columns.
- **Team pages live under `/teams/:subdomain`**, including the team's settings
  (`/teams/:subdomain/settings`, `/settings/cards`, `/settings/managers`). The URL names
  the team a page acts on; there is no hidden "current team" for a page to change.
- **Organizations are `/orgs/:slug`** on both sites. Admin pages use the id:
  `/admin/orgs/:id`.
- **Nothing fixed directly under `/teams/` or `/orgs/`.** It would block a team or an
  organization with that name. That's why sign-up is `/signup`, not `/teams/new`.
- **Top-level paths are a short list**: `teams`, `orgs`, `admin`, `account`, `signup`,
  `login`, `logout`, `s`, `attendance`, `wallet`, `styles`, `terms`, `privacy`, and `dev` in
  development. A
  new one is added to the router test on purpose.
- **Anything printed or texted goes through `/s/` or the verify site**, so it stays short
  and never depends on a team page's path.
- **Build paths one way**: `~p"/teams/#{team}/members"`. `App.Model.Team` derives
  `Phoenix.Param` on `subdomain`, and `App.Model.Organization` on `slug`, so a future move
  is one router change and a grep.

## Held outside the app

Devices, Google, Apple, and shared links hold these. They don't move.

- `/wallet/v1/…`: Apple's web service path, in every issued pass.
- `/s/:code` and `/attendance/:token`: shared attendance links.
- `/teams/:subdomain/logo`: Google Wallet objects fetch it.
- On the verify site: `/:code` (the QR code), `/:code/photo`, `/:code/banner` (the Google
  Wallet banner), `/orgs/:slug`, and `/letters/:ref` (the QR code on every tax credit
  letter since #207).

Card images always use SAR Duty's verify host, even for an organization with its own,
since Google Wallet objects hold the banner URL.
