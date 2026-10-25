# Organizations

<!-- cspell:ignore OSARVA SRVTC -->

A team can belong to one parent organization, like BCSARA (bcsara.com). Its cards and
check pages then carry the organization's name and logo instead of SAR Duty's. Issue #87
has the design of its own verify host.

## Its space and its admins (#512)

Each organization has its own space at `/orgs/:slug`, beside a team's space, SAR Duty
admin, and account settings. A SAR Duty admin creates it in Admin › Organizations, then
types in its **organization admins'** emails on its Organization admins tab.

- **Organization admins** log in with that email alone, like a login grant: no D4H match
  (`Accounts.may_log_in?/2`). A SAR Duty admin's login still needs D4H (#141), so the
  form refuses a SAR Duty admin's email. Organization admins can't add other organization
  admins. Opening their pages stamps `organization_admins.last_seen_at`, at most hourly,
  never `users.last_seen_at`, which would make their own team look recently used.
- **They keep** its name, short name, website, time zone, and logo (General), and its
  hours tags (Hours tags). Saving General queues pass updates for its teams; hours tags
  are not on a pass, so saving them records an `organization_hours_tags_changed` event
  with the old and new tags instead.
- **They see each team's totals, never its people**: no member names, emails, phone
  numbers, or team pages. A test sweeps every `/orgs` page from the router for seeded
  names, emails, and phones.
- **The organization's time zone** is for dates about it, such as an organization
  admin's Last seen. A team's row keeps the team's own zone.
- **Who acts is checked in the code that acts**, not just the page:
  `OrganizationAdmin.add/3` and `remove/3` take SAR Duty admins only.
- **Only SAR Duty admins add and remove its teams**, from its Teams page. Adding a team
  is when a SAR Duty admin checks it is real, so its organization admins can then turn
  on its ID cards ([member-cards.md](member-cards.md)). Add a team offers only teams in
  no organization; a SAR Duty admin moves a team by removing it from one organization,
  then adding it to the other. `SetTeamOrganization` does both: it refuses a team whose
  own hours tags would repeat the organization's, queues its pass updates, records an
  event, and emails its team admins (`TeamAdminMailer`, Reply-To `support@sarduty.com`).
  Its ID cards stay on or off. Team settings › Team admins lists the team's organization
  admins and the SAR Duty admins, so its team admins know who to reach.
- The `/orgs/:slug` pages share one `live_session` and an `:ensure_org_access` hook that
  404s anyone who is neither its organization admin nor a SAR Duty admin.

## What an organization changes today

- **Its verify page**, `verify.sarduty.com/orgs/<slug>`, shows the organization's logo and
  short name in the bar and its name in the footer. The check itself is unchanged, since
  it works for any card. The host on the right and the "Powered by" footer stay, since the
  host is what checkers are told to look for.
- **A card's result keeps the team's brand.** The organization's name goes under the team
  name, as plain text. Its "Check another card" button goes back to the organization's
  verify page.
- **The back of the pass** says who issued it: "North Shore Rescue, a member team of BC
  Search and Rescue Association", with no SAR Duty. The front doesn't change.

- **Which D4H tags count as hours** on its teams' tax credit letters (#289). The OSARVA
  teams tag activities `SRVTC Primary Activity` and `SRVTC Secondary Activity`, and
  can't change them. Blank keeps `Primary Hours` and `Secondary Hours`. Letters still
  say "Primary Hours" and "Secondary Hours", SARVAC's terms; only the tags that feed
  them change. Letters already made keep their hours, and the letter list marks the
  ones that changed. A team names any tag its organization leaves blank, and a team with
  no organization names its own, in **Settings → Hours tags** (#323).

Saving an organization's General settings queues a pass update for each of its teams, so
phones pick up the new back of the pass in a minute or so.

The card's QR code and "how to check" text still say `verify.sarduty.com`. That changes
only when the organization has its own host.

## Giving an organization its own verify host

Not built yet. When an organization wants `verify.bcsara.com`:

1. **They add a DNS record**: `verify` CNAME `verify.sarduty.com`. Organization settings
   will show the exact record once #87 builds this. The target is the verify host, not the app, so if
   verify ever moves, one record of ours moves every organization. On Cloudflare it must
   be DNS only (grey cloud), or Fly can't issue the certificate.
2. **They agree** to give notice before removing it, so cards can move back to
   `verify.sarduty.com` first.
3. **We add the certificate**: `fly certs add verify.bcsara.com`, then
   `fly certs show verify.bcsara.com` until it's issued.
4. **We ship the code** that reads the host, below, and set it on the organization.

The router already serves the verify site on any `verify.` host, so the page renders on
the new host as soon as DNS and the certificate work. Its LiveView won't connect until
`check_origin` allows the host.

What the code for step 4 needs:

- A `verify_host` on the organization, set in /admin once the certificate is issued.
- `MemberCard.qr_url/2` and `MemberCard.how_to_check/1` take the team's host. The QR
  change alters every pass's fingerprint, so each phone gets one silent update.
- `check_origin` as an MFA that allows `sarduty.com`, `verify.sarduty.com`, and every
  organization host. Not `:conn`: behind Fly's proxy the app sees http on 8080.
- The page's scanner trusts every organization host
  ([Web.VerifyHost.trusted_hosts/0](../lib/web/verify_host.ex)).
- Branding by host: a `verify.` host that matches an organization shows its brand on the
  start page; an unknown one redirects to `verify.sarduty.com`. Only brand hosts we've
  added, since anyone can point a domain at us.
- A card opened on another trusted host redirects to its own, so the address bar always
  matches what the card says.
