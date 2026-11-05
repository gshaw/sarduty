# Outbox

Email and texts SAR Duty keeps instead of sending, as `App.Model.OutboxMessage` rows.

- **A Try a demo team's email, always** ([demo.md](demo.md)). `App.Mailer.deliver/2`
  keeps any email marked with a demo team (`Mailer.for_team/2`) in the team's Outbox,
  on every server. The demo's banner links it, at `/teams/:subdomain/outbox`. Each
  message shows like the email previews, with From, To, Subject and Date above it, and
  its links live, so a reminder's reply link works as it would for the member.
- **Everything in dev.** Email goes through `App.Adapter.Outbox` unless
  `DEV_SEND_EMAIL=true` sets Cloudflare's adapter, and `App.Adapter.Twilio` keeps a text
  unless `DEV_SEND_SMS=true`. Login codes land there. `/dev/outbox` shows them all,
  linked from the foot of every page, with Empty the outbox.

Tests use `Swoosh.Adapters.Test` for real teams' email; a demo team's lands in the
Outbox in tests too. Twilio is stubbed with `Req.Test`.

A team's email that skips `Mailer.for_team/2` isn't known as the demo's, so it would be
sent. A demo's members all have example.com addresses, which take no mail, so it
reaches nobody; still, every mailer for a team's email calls `for_team/2`.

An open Outbox page shows a new message at once (`OutboxMessage.topic/0`). The rows go
with the team (`App.Operation.DeleteTeam`); dev's stay until emptied.
