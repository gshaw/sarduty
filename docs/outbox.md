# Outbox

Email and texts SAR Duty keeps instead of sending, as `App.Model.OutboxMessage` rows.

- **A Try a demo team's email, always** ([demo.md](demo.md)). `App.Mailer.deliver/2`
  keeps any email marked with a demo team (`Mailer.for_team/2`) in the team's Outbox,
  on every server. The demo's banner links it, at `/teams/:subdomain/outbox`. Each
  message shows like the email previews, with From, To, Subject and Date above it, and
  its links live, so a reminder's reply link works as it would for the member. Its
  attachments are kept too (`App.Model.OutboxAttachment`) and listed under Attached: a
  tax credit letter's PDF opens in the browser, and a wallet pass downloads.
- **Everything in dev.** Email goes through `App.Adapter.Outbox` unless
  `DEV_SEND_EMAIL=true` sets Cloudflare's adapter, and `App.Adapter.Twilio` keeps a text
  unless `DEV_SEND_SMS=true`. Login codes land there. `/dev/outbox` shows them all,
  linked from the foot of every page, with Empty the outbox.

Tests use `Swoosh.Adapters.Test` for real teams' email; a demo team's lands in the
Outbox in tests too. Twilio is stubbed with `Req.Test`.

Every email and text says whose it is, so none skips a demo's Outbox by mistake. An
email is piped through `Mailer.for_team/2` or `Mailer.for_no_team/1` (a login code, a
new team's notice), and `Mailer.deliver/2` raises on one with neither.
`App.TeamMarkTest` checks that each function calling `Mailer.deliver` marks its email
there. `Twilio.send_sms/3` takes a team id or `:no_team`, with no default. The mark
stops a forgotten one, not a wrong one: a team's email marked `for_no_team` is sent.

An open Outbox page shows a new message at once (`OutboxMessage.topic/0`). A demo's list
marks New what arrived since its last visit (`demo_teams.outbox_seen_at`), and the
banner says so too ([demo.md](demo.md)); dev's has no New. The rows go with the team
(`App.Operation.DeleteTeam`); dev's stay until emptied.
