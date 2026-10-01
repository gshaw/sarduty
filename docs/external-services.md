# External services

Every boundary the app crosses, what it needs, and what breaks without it. Environment
variables are read in [config/runtime.exs](../config/runtime.exs) unless noted.

## D4H

The system of record. Each team has an API host (its region) and a bearer token, both in
the database; there is no D4H environment variable. Access keys come from D4H personal
access tokens ([how to get one](https://help.d4h.com/article/377-obtaining-an-api-access-key)).
Reads are everywhere. The writes are the attendance `PATCH` and group membership adds and
removes from the group review page. See [d4h-sync.md](d4h-sync.md).

## Mapbox

[lib/app/adapter/mapbox.ex](../lib/app/adapter/mapbox.ex). Geocodes member addresses and
gets driving distances for the mileage report, and draws the static map on the activity
page. The token is a query parameter.

- `MAPBOX_ACCESS_TOKEN` — read with `fetch_env!` in **every** environment, so the app,
  the tests, and migrations won't start without it. `dummy` is fine locally unless you are
  testing mileage.

## Mail

Swoosh. Production sends through Cloudflare Email Sending's REST API with
[App.Adapter.CloudflareEmail](../lib/app/adapter/cloudflare_email.ex), since Swoosh has
no Cloudflare adapter. Dev uses the local mailbox at `/dev/mailbox` unless both
variables below are set in dev too; tests use `Swoosh.Adapters.Test`. Mail comes from
`noreply@sarduty.com`: account emails, and tax credit letters with the PDF attached.

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

## Litestream and Tigris

Litestream replicates `/mnt/sarduty/sarduty.db` to the Tigris bucket in
[litestream.yml](../litestream.yml). Its credentials are Fly secrets, not in the repo.
Team logos on the same volume are not replicated. See [deployment.md](deployment.md).

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

Passwords, access keys, tokens, and the cookie header are filtered before sending, at
every level of the params ([Web.HoneybadgerFilter](../lib/web/honeybadger_filter.ex)).
Request paths are not, so reset and confirm links reach Honeybadger the same way they
reach the logs.

## MCP endpoint

Off. The test version served `GET|POST /:subdomain/mcp` to every team behind one
`MCP_ACCESS_KEY` sent as `?access=…`, and returned member home addresses. Its controller,
[lib/web/controllers/mcp_controller.ex](../lib/web/controllers/mcp_controller.ex), has
no route until #28 brings it back as an opt-in team feature: per-team tokens in an
`Authorization` header, and member names, email, and phone but never addresses.

## Other secrets

| Variable          | Purpose                                                          |
| ----------------- | ---------------------------------------------------------------- |
| `SECRET_KEY_BASE` | Phoenix endpoint secret. Production only.                        |
| `CLOAK_KEY`       | Base64 AES-GCM key for every `EncryptedString`. Production only. |
| `TEAM_LOGO_PATH`  | Directory for team logos. Read when a logo is used, not at boot. |
| `DATABASE_PATH`   | SQLite file. Set in `fly.toml`.                                  |
| `PHX_HOST`        | Public host. Set in `fly.toml`.                                  |

Losing `CLOAK_KEY` makes every access key, member contact detail, and letter unreadable.
Dev and test use a key committed in `config/config.exs`.
