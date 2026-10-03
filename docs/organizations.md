# Organizations

A team can belong to one parent organization, like BCSARA (bcsara.com). Its cards and
check pages then carry the organization's name and logo instead of SAR Duty's. An admin
sets organizations up at `/admin/organizations`; teams can't join or leave one
themselves. Issue #87 has the design.

## What an organization changes today

- **The verify site's bar** shows the organization's logo and short name, on its start
  page `verify.sarduty.com/o/<slug>` and for a card from one of its teams. The host on the
  right and the "Powered by" footer stay, since the host is what checkers are told to look
  for.
- **The result** says "Member team of BC Search and Rescue Association" under the team.
- **The back of the pass** says who issued it: "North Shore Rescue, a member team of BC
  Search and Rescue Association", with no SAR Duty. The front doesn't change.
- **A team without a D4H logo** gets the organization's logo, not SAR Duty's.

Saving an organization queues a pass update for every team it had or now has, so phones
pick up the new back of the pass in a minute or so.

The card's QR code and "how to check" text still say `verify.sarduty.com`. That changes
only when the organization has its own host.

## Giving an organization its own verify host

Not built yet. When an organization wants `verify.bcsara.com`:

1. **They add a DNS record**: `verify` CNAME `verify.sarduty.com`. The organization's
   admin page shows the exact record. The target is the verify host, not the app, so if
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
