# External services

Every boundary the app crosses, what it needs, and what breaks without it. Environment
variables are read in [config/runtime.exs](../config/runtime.exs) unless noted.

## D4H

The system of record. Each team has an API host (its region) and a bearer token, both in
the database; there is no D4H environment variable. Access keys come from D4H personal
access tokens ([how to get one](https://help.d4h.com/article/377-obtaining-an-api-access-key)).
Reads are everywhere. The writes are the attendance `PATCH` and group membership adds and
removes from the group review page. See [d4h-sync.md](d4h-sync.md).

## SAR Duty Records

A separate app at `records.sarduty.com` for teams without D4H, serving D4H's v3 API. A
Records team's API host is Records' host and its key a Records key, both in the database
like a D4H team's. The same adapter calls it. See [records.md](records.md).

- `RECORDS_HOST` — dev only, optional: points SAR Duty at a local Records.

## Mapbox

[lib/app/adapter/mapbox.ex](../lib/app/adapter/mapbox.ex). Geocodes member addresses and
gets driving distances for the mileage report, and draws the static maps on the team home
and activity pages. The token is a query parameter, and it never reaches a browser: map
images come from `/maps/<key>` ([Web.MapImage](../lib/web/map_image.ex)), where the key
is a Mapbox path the app signed. The server adds the token, fetches the image, and passes
on Mapbox's cache header. Since every call comes from the server, the token can't have URL
restrictions: Mapbox checks those against the browser's `Referer`, so they block the
mileage report and the map proxy alike.

- `MAPBOX_ACCESS_TOKEN` — read with `fetch_env!` in **every** environment, so the app,
  the tests, and migrations won't start without it. `dummy` is fine locally unless you are
  testing mileage.

## Mail

Swoosh. Production sends through Cloudflare Email Sending's REST API with
[App.Adapter.CloudflareEmail](../lib/app/adapter/cloudflare_email.ex), since Swoosh has
no Cloudflare adapter. Dev uses the local mailbox at `/dev/mailbox`, linked from the
footer and the login pages, unless `DEV_SEND_EMAIL=true` and both variables below are set:
a dev database is often a copy of production, so real mail could reach real members. Tests
use `Swoosh.Adapters.Test`. Mail comes from
`noreply@sarduty.com`: login codes, and tax credit letters with the PDF attached. Login
is by emailed code, or texted when [Twilio](#twilio) is set up, so without mail most
people cannot log in; existing sessions last 60 days.

- `CLOUDFLARE_ACCOUNT_ID` — required in production.
- `CLOUDFLARE_EMAIL_TOKEN` — required in production. An account API token with only the
  **Email Sending: Edit** permission.

sarduty.com is onboarded under **Email Service > Email Sending** in the Cloudflare
dashboard, which added and locked the DNS records that authenticate its mail. Sending
needs the Workers Paid plan: 3,000 emails a month are included. The dashboard's
**Activity log** shows each message and whether it was delivered or bounced. A message
over 5 MiB, attachments included, is refused.

Creating a tax credit letter emails it from a `Task.start`, so the "Email sent" flash
appears before delivery is known.

## Twilio

[App.Adapter.Twilio](../lib/app/adapter/twilio.ex) texts login codes, posting to the
Messages API with an API key. Optional: without all four variables the login page offers
no text, and a posted number goes back to the email form. The account is Andrew's, with a
number of its own for SAR Duty. D4H's callout number on the same account must not be
used: replies to it go to D4H, and a STOP to it would block D4H callouts too, since
Twilio honours STOP per sender number.

A number logs in only when it leads to exactly one email that may log in, from the
phones on current members. A code texted can't be entered as one emailed, or the other
way. `Web.LoginLimit` allows 3 texts per number per 15 minutes. Dev logs each text instead
of sending it unless `DEV_SEND_SMS=true`, like `DEV_SEND_EMAIL`. Tests ignore the
variables and stub Twilio with `Req.Test`.

- `TWILIO_ACCOUNT_SID` — the account's `AC…` id.
- `TWILIO_API_KEY_SID` — an API key's `SK…` id. A restricted key that can only send
  messages is enough.
- `TWILIO_API_KEY_SECRET` — that key's secret, shown once when the key is made.
- `TWILIO_FROM_NUMBER` — the sending number in E.164, like `+16045550100`.

Not built yet: an inbound webhook for replies (`/webhooks/twilio/sms`, checking
`X-Twilio-Signature`). Until then leave the number's incoming message webhook empty.

## Apple Wallet

Signs member ID card passes ([BuildApplePass](../lib/app/operation/build_apple_pass.ex),
[Service.ApplePass](../lib/service/apple_pass.ex)) with a Pass Type ID certificate from
Gerry's Apple developer account. Signing runs the `openssl` CLI, which the Fly image
installs. Apple's WWDR G4 intermediate is public and lives in `priv/apple/`. All four
variables are optional: without them the ID Card tab offers no pass.

- `APPLE_PASS_TYPE_ID` — `pass.com.sarduty.member-card`.
- `APPLE_TEAM_ID` — the developer account's team ID.
- `APPLE_PASS_CERTIFICATE` — the pass certificate, PEM text.
- `APPLE_PASS_PRIVATE_KEY` — its private key, PEM text.

The same certificate signs in to Apple Push Notification service
([App.Adapter.APNs](../lib/app/adapter/apns.ex)), which tells phones a pass changed.
Passes also call back to `/wallet/v1/…`, so those routes must stay public.

The certificate expires on 2027-10-30. Make a new one with
`asc certificates create --certificate-type PASS_TYPE_ID`, then update the secrets.
Passes already on phones keep working.

## Google Wallet

Sends member ID card passes to Google
([BuildGooglePass](../lib/app/operation/build_google_pass.ex),
[App.Adapter.GoogleWallet](../lib/app/adapter/google_wallet.ex)) as the
`sarduty-wallet@sar-duty.iam.gserviceaccount.com` service account, in Google Cloud
project `sar-duty`. The issuer account is in the
[Pay & Wallet Console](https://pay.google.com/business/console/) as "SAR Duty", where the
service account is a Developer. Setup is in #74. Both variables are optional: without
them the ID Card tab offers no Google pass.

- `GOOGLE_WALLET_ISSUER_ID` — `3388000000023212691`.
- `GOOGLE_WALLET_SERVICE_ACCOUNT` — the service account's JSON key file, on one line.
  Gerry's copy is in `~/.sarduty-wallet/`.

Until Google grants publishing access, passes say "[TEST ONLY]" and only the console's
users can save them. Dev and production share the issuer; ids carry the host, so they
don't collide.

## Litestream and Cloudflare R2

Litestream replicates `/mnt/sarduty/sarduty.db` to the `sarduty-db` R2 bucket in
[litestream.yml](../litestream.yml), using the account in `CLOUDFLARE_ACCOUNT_ID`.
Team logos on the same volume are not replicated. See [deployment.md](deployment.md).

- `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` — Fly secrets, from an R2 API token
  with **Object Read & Write** on `sarduty-db` only. Without them Litestream logs
  errors and the app runs without a backup.

Litestream 0.5 has no client-side encryption, so the replica holds readable data. R2
encrypts it at rest; reading it takes the bucket token or the Cloudflare account.

- `BACKUP_AGE_RECIPIENT` — in `.mise.local.toml`, the public half of an
  [age](https://age-encryption.org) key. [backups/backup.sh](../backups/backup.sh)
  encrypts each local snapshot to it. The private half is in the password manager, and
  nothing decrypts a snapshot without it.

## Healthchecks

- `HEALTHCHECKS_URL` — optional. Pinged after each successful team refresh, so a missed
  ping means the daily sync stopped.

## Honeybadger

Error reports and Insights (request, query, LiveView, and job timings), configured in
[config/config.exs](../config/config.exs). Errors come from the router
(`use Honeybadger.Plug`), crashed processes through the logger, and Oban jobs that fail
their last attempt through [App.Worker.ErrorReporter](../lib/app/worker/error_reporter.ex).
A team refresh with a missing or rejected D4H key cancels instead of failing, so it shows
on `/admin` and never reaches Honeybadger. Dev and test send nothing.

- `HONEYBADGER_API_KEY` — a Fly secret, read by the `honeybadger` library itself.
  Without it in production the app still boots, logs
  `Mandatory config key :api_key not set`, and reports nothing.

Any key whose name contains `key`, `token`, `code` or `password`, and the cookie header,
is filtered before sending, at every level, for errors and Insights events alike
([Web.HoneybadgerFilter](../lib/web/honeybadger_filter.ex)). Attendance tokens, short
link codes and card codes are cut from paths, URLs and the referrer, the same way
[Web.RequestLog](../lib/web/request_log.ex) cuts them from Fly's request logs (#176).

## MCP endpoint

Agents call in rather than SAR Duty calling out: `POST /teams/:subdomain/mcp`, read-only
apart from proposals a team admin must send,
for teams an admin turns it on for (#28). Each manager's token is in the database, hashed,
so there is no environment variable. The old test version's `MCP_ACCESS_KEY` and its
`?access=…` parameter are gone; unset the Fly secret if it is still there. See
[mcp.md](mcp.md).

## Other secrets

| Variable          | Purpose                                                          |
| ----------------- | ---------------------------------------------------------------- |
| `SECRET_KEY_BASE` | Phoenix endpoint secret. Production only.                        |
| `CLOAK_KEY`       | Base64 AES-GCM key for credentials. Production only.             |
| `TEAM_LOGO_PATH`  | Directory for team logos. Read when a logo is used, not at boot. |
| `DATABASE_PATH`   | SQLite file. Set in `fly.toml`.                                  |
| `PHX_HOST`        | Public host. Set in `fly.toml`.                                  |

Losing `CLOAK_KEY` makes every D4H access key and Apple pass token unreadable.
Dev and test use a key committed in `config/config.exs`.
