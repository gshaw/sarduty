# External services

Every boundary the app crosses, what it needs, and what breaks without it. Environment
variables are read in [config/runtime.exs](../config/runtime.exs) unless noted.

## D4H

The system of record. Each team has an API host (its region) and a bearer token, both in
the database; there is no D4H environment variable. Access keys come from D4H personal
access tokens ([how to get one](https://help.d4h.com/article/377-obtaining-an-api-access-key)).
Reads are everywhere; the only write is the attendance `PATCH`. See
[d4h-sync.md](d4h-sync.md).

## Mapbox

[lib/app/adapter/mapbox.ex](../lib/app/adapter/mapbox.ex). Geocodes member addresses and
gets driving distances for the mileage report, and draws the static map on the activity
page. The token is a query parameter.

- `MAPBOX_ACCESS_TOKEN` — read with `fetch_env!` in **every** environment, so the app,
  the tests, and migrations won't start without it. `dummy` is fine locally unless you are
  testing mileage.

## Mail

Swoosh. Production uses ZeptoMail; dev uses the local mailbox at `/dev/mailbox` unless
`ZEPTO_MAIL_KEY` is set in dev too; tests use `Swoosh.Adapters.Test`. Mail comes from
`noreply@sarduty.com`: account emails, and tax credit letters with the PDF attached.

- `ZEPTO_MAIL_KEY` — required in production.

Creating a tax credit letter emails it from a `Task.start`, so the "Email sent" flash
appears before delivery is known.

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
