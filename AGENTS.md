# AGENTS.md

## Big picture

- SAR Duty is a **Phoenix 1.8 LiveView** app for search and rescue team managers. D4H is
  each team's system of record; SAR Duty copies it into a local **SQLite** database and
  builds what D4H doesn't: tax credit letters, mileage reports, attendance cleanup, and
  group qualification rules.
- It is multi-team. Team pages live under `/teams/:subdomain/…`, and every query that
  reads team data filters by `team_id`. URL rules and the URLs that can't move are in
  [docs/urls.md](docs/urls.md).
- Production is one Fly machine with SQLite on a volume, replicated by Litestream. See
  [docs/deployment.md](docs/deployment.md).
- Start with [docs/README.md](docs/README.md) for the map.

## Architecture & code organization

- **Web**: [lib/web/live/](lib/web/live) LiveViews, [lib/web/controllers/](lib/web/controllers),
  and [lib/web/components/](lib/web/components). A LiveView picks its layout with
  `use Web, :live_view_app_layout` (team pages), `:live_view_narrow_layout` (auth and
  settings forms), or `:live_view_marketing_layout` (public pages) — see
  [lib/web.ex](lib/web.ex). The layout macro also decides which components are imported.
- **Operations**: [lib/app/operation/](lib/app/operation) hold side effects and
  orchestration, one module per operation with a `call` entry point:
  `App.Operation.CreateTaxCreditLetter.call(…)`.
- **Adapters**: [lib/app/adapter/d4h.ex](lib/app/adapter/d4h.ex) with one struct per D4H
  resource in [lib/app/adapter/d4h/](lib/app/adapter/d4h), and
  [lib/app/adapter/mapbox.ex](lib/app/adapter/mapbox.ex). This is the only layer that knows
  an endpoint or a third-party JSON field name.
- **Models**: [lib/app/model/](lib/app/model) are Ecto schemas (`use App, :model`), with
  their queries as functions on the model.
- **View models**: [lib/app/view_model/](lib/app/view_model) are embedded schemas
  (`use App, :view_model`) that validate filter and form params.
- **View data**: [lib/app/view_data/](lib/app/view_data) bundle the read-only queries for
  one page.
- **Workers**: [lib/app/worker/](lib/app/worker) are Oban jobs — today, the daily D4H
  refresh.
- **Fields and validators**: [lib/app/field/](lib/app/field) (`EncryptedString`,
  `TrimmedString`) and [lib/app/validate/](lib/app/validate).
- **Service**: [lib/service/](lib/service) are stateless helpers — `Service.Format`,
  `Service.Convert`, `Service.PDFLetter`. No database, no HTTP.
- **Accounts**: [lib/app/accounts/](lib/app/accounts) is users who log in with an emailed
  link (no passwords), with `phx.gen.auth`-style sessions (`current_user` and
  `current_team`, not `current_scope`) and an admin flag. Access comes from D4H: a user
  reaches a team when their email matches a member D4H makes an Owner or Editor
  (`Team.get_managed_by/2`). Admins reach every team.

## External integrations (know where to look)

- **D4H v3 API**: [lib/app/adapter/d4h.ex](lib/app/adapter/d4h.ex). Each team has its own
  API host (region) and bearer token. Almost everything reads. Every write is a change
  set, applied by `App.Operation.ApplyChangeSet`: attendance from the door and from a
  pasted report, and group membership adds and removes. See
  [docs/change-sets.md](docs/change-sets.md). How the local copy is kept fresh is in
  [docs/d4h-sync.md](docs/d4h-sync.md).
- **Mapbox**: geocoding and driving distances for the mileage report, and the static map
  on the activity page.
- **Cloudflare Email Sending** through Swoosh, with our own adapter in
  [lib/app/adapter/cloudflare_email.ex](lib/app/adapter/cloudflare_email.ex): mail in
  production. Dev uses the local mailbox at `/dev/mailbox`.
- **Litestream to Cloudflare R2**: continuous SQLite backup.
- **MCP**: a trial at `/teams/:subdomain/mcp` (#28). An admin turns it on per team in
  `/admin/mcp`, and managers create personal bearer tokens in team settings. Tools in
  [lib/app/mcp/tool/](lib/app/mcp/tool) are scoped to the token's team and build output
  from an explicit field allowlist: never contact details, addresses, coordinates, letter
  text, or keys. They only read, except `propose_attendance_changes`, which saves a
  change set for a team admin to send. A tool may propose a change set, never apply one.
  See [docs/mcp.md](docs/mcp.md).

Every boundary, its credentials, and what breaks without it:
[docs/external-services.md](docs/external-services.md).

## Local setup & keys

- First-time setup is in [README.md](README.md). Secrets go in `.mise.local.toml`
  (gitignored); start from `.mise.example.toml`.
- `config/runtime.exs` reads `MAPBOX_ACCESS_TOKEN` in **every** environment, so
  `mix test`, `mix phx.server`, and `mix ecto.migrate` fail without it. Any value works
  when you are not testing the mileage report: `MAPBOX_ACCESS_TOKEN=dummy mix test`.
- D4H tokens are not environment variables. Each team has one key, a D4H personal access
  token pasted into team settings, stored encrypted (Cloak) in the database.
- The dev server is `https://sarduty.test` through puma-dev, proxying to port 4025.

## Shell environment

- Developers on this project use Apple Silicon Macs, and Homebrew installs tools under
  `/opt/homebrew/bin`.
- When commands are run from GUI-launched environments, PATH may not include Homebrew.
  If `mise` is missing, prepend Homebrew to PATH before running shell commands:

```sh
if [ -d /opt/homebrew/bin ]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
```

## Developer workflow (repo-specific)

- Tooling is managed by `mise` (see `.mise.toml`). `mise run check` formats, compiles
  with warnings as errors, lints with Credo, and spell-checks and lints the Markdown.
  `mise run test` runs the suite; `mise run ci` runs both. `mix precommit` is an alias for
  `mise run ci`.
- **Read the counts, not just the exit code.** Credo prints `N source files`,
  markdownlint prints `Linting: N files`, and ExUnit prints `Result: N passed`. A green
  run over a handful of files checked nothing; if a count looks small, the checker is
  misconfigured rather than satisfied.
- CI runs `mise run -c ci-static-analysis` and `mise run test` on every PR
  ([.github/workflows/ci.yml](.github/workflows/ci.yml)). Don't merge on red.
- **Deploys are manual**: `fly deploy` from `main`. Never deploy, and never read or write
  production data, unless asked. The how is in [docs/deployment.md](docs/deployment.md).
- Create migrations with `mix ecto.gen.migration name_with_underscores`. Migrations run
  when the app boots (`App.Release.migrate/0` in `App.Application.start/2`), in every
  environment — there is no release command.
- For agent-driven work, keep progress, decisions, and outcomes on the related GitHub
  issue or PR (prefer the PR when one exists).
- **Bug issues** open with the three sections in
  [.github/ISSUE_TEMPLATE/bug_report.md](.github/ISSUE_TEMPLATE/bug_report.md) — **Steps
  to reproduce**, **Expected**, **Actual** — before any diagnosis. State the observable
  failure first; analysis and a proposed fix go after. Tracking and enhancement issues do
  not use this shape.
- **Issue and PR bodies are not hard-wrapped.** One line per paragraph and let GitHub
  reflow — unlike the Markdown in this repo, which is wrapped. Numbered reproduction steps
  stay one step per line.
- **Branch naming:** `<slug>` (e.g. `group-rule-apply`), or `<issue>-<slug>` when a GitHub
  issue exists (e.g. `20-group-rule-apply`). kebab-case, 2–3 words, ≤ ~25 chars. **No
  path prefixes or slashes** (`claude/…`, `copilot/…`, `feature/…`). If your tooling
  defaults to a prefixed name, rename the branch before pushing.

## Tests

- ExUnit. `App.DataCase` for anything that touches the database, `Web.ConnCase` for
  controllers and LiveViews. Fixtures are `App.DataFixtures`
  ([test/support/fixtures/app_fixtures.ex](test/support/fixtures/app_fixtures.ex)) and
  `App.AccountsFixtures`.
- **Functional core, imperative shell.** An Operation that warrants tests exposes a pure
  function — values in, value out, no `Repo`, no HTTP, and `now` passed in rather than
  read. `call` loads the data, delegates, and writes back. Tests call only the pure
  function, with `use ExUnit.Case, async: true`. Reference:
  [BuildGroupRulePreview.plan/4](lib/app/operation/build_group_rule_preview.ex) and
  [its test](test/app/operation/build_group_rule_preview_test.exs).
- **Never call D4H or Mapbox from a test.** In tests every D4H request goes to
  `Req.Test` (`config/test.exs`), so stub it with `Req.Test.stub(App.Adapter.D4H, …)`; a call
  with no stub fails. Mapbox goes to `Req.Test` the same way. Oban runs with
  `testing: :inline`, so a test that enqueues a refresh runs it.
- LiveView tests use `Phoenix.LiveViewTest` and target element IDs (`has_element?/2`),
  not raw HTML.
- Test files mirror `lib/`: `lib/app/operation/x.ex` → `test/app/operation/x_test.exs`.
  What gets tested and why is in [docs/testing-strategy.md](docs/testing-strategy.md).

## When writing code

- **One module per file**, named after the module in snake_case. Folders are snake_case
  too.
- **New side effects go in an Operation**, not a LiveView `handle_event`. Some older
  LiveViews call the D4H adapter directly (`ActivityAttendanceLive`,
  `ActivityMileageLive`, `Settings.TeamLive`); don't copy that.
- **Every D4H write is a change set.** Build rows with `ChangeSet.propose!/2` and apply
  them with `ApplyChangeSet.call/4`. Never call D4H's write functions from anywhere
  else; a test fails if you do.
- **Only adapters know D4H's JSON.** A new D4H resource is a struct in
  `lib/app/adapter/d4h/` with a `build/1` that maps the response, plus a fetch function in
  `d4h.ex`. Use `Req`; never `:httpoison`, `:tesla`, or `:httpc`.
- **D4H ids live in `d4h_*_id` columns.** Foreign keys are local ids. Route params are
  local ids; D4H calls take the `d4h_*_id`.
- **Scope every team query, including joins and deletes.** Filter the member's or
  qualification's `team_id`, not just the row you started from, and look a record up
  through the current team before changing it — never by a bare id from the client.
- **Cloak is for credentials**: D4H access keys and pass tokens use
  `App.Field.EncryptedString`. Personal data such as member contact details and letter
  text is plain. R2 encrypts the replica at rest and local backups use age (#111). Give
  personal fields `redact: true`.
- **Times are stored in UTC** and shown in the team's zone with `Service.Format`
  (`Service.Format.date_long(datetime, team.timezone)`).
- **Text people read follows [docs/writing.md](docs/writing.md).** Any page copy, button,
  label, hint, error, flash, email, PDF, or pass text you write or change uses its rules
  and its glossary terms. Run its checklist before you commit.
- **The look comes from the design system**, shown at `/styles`. Colours, type sizes,
  and spaces are tokens in [assets/css/tokens.css](assets/css/tokens.css), with light and
  dark values. Use the theme's colour names (`text-secondary-1`, `bg-base-2`) or the
  tokens, never raw Tailwind colours like `text-zinc-600`, which don't follow dark mode.
- Buttons are `<.button variant={:success} size={:sm}>`; give it `navigate` or `href` for a
  link styled as a button. Badges are `<.badge kind={:incident}>`. Both check their values
  at compile time, so never write `class="btn btn-success"` or `class="badge"` by hand.
- Phoenix hazards that are easy to trip on:
  - HEEx interpolates with `{…}` in attributes and bodies, and `<%= … %>` only for block
    constructs (`if`, `case`, `for`). Class lists use `[…]`. There is no `else if`; use
    `cond`.
  - Forms are `<.form for={@form} id="…">` built from `to_form/2`, with
    `<.input field={@form[:x]}>`. Never pass a changeset to a template.
  - Preload associations a template will read. Never cast fields set in code (`team_id`,
    `member_id`); put them on the struct.
  - Never call `String.to_atom/1` on user input.
  - Use `<.link navigate>` / `<.link patch>` and `push_navigate` / `push_patch`, not the
    deprecated `live_redirect` / `live_patch`.

## Suppressions

Every checker has an inline escape hatch. Use it rather than the central config.

- **Suppress at the narrowest scope that works, and say why there.** The suppression goes
  in the file that provoked it, with a short reason — not into `.credo.exs` or
  `.cspell.yaml`. A suppression in a config file is a decision nobody reading the code will
  see.
- **Central config is only for what recurs across files.** When you are about to write the
  same suppression into a second file, move it to the config and delete the first one.
- **"False positive" is not a reason.** Say what the thing is: whose API, which D4H field,
  why the function is long.
- **Never suppress to make a check pass.** If you have not confirmed the code is correct,
  the check has done its job.

| Checker      | Inline form                                                                    |
| ------------ | ------------------------------------------------------------------------------ |
| Credo        | `# credo:disable-for-next-line Credo.Check.<Name>`, or `disable-for-this-file` |
| cspell       | `# cspell:ignore …` in Elixir, `<!-- cspell:ignore … -->` in Markdown          |
| markdownlint | `<!-- markdownlint-disable-next-line MD0xx -->`                                |

## Guidance & standards

Project-specific architecture lives in [docs/](docs/README.md). Before a non-trivial
change, read the relevant doc:

- **Layers, and where new code goes** → [docs/README.md](docs/README.md).
- **How D4H data reaches the database, and what never gets deleted** →
  [docs/d4h-sync.md](docs/d4h-sync.md).
- **Member and activity history** → [docs/change-history.md](docs/change-history.md).
- **Group qualification rules** → [docs/group-rules.md](docs/group-rules.md).
- **Every external service and its credentials** →
  [docs/external-services.md](docs/external-services.md).
- **Fly, Litestream, and changing production data** →
  [docs/deployment.md](docs/deployment.md).
- **What is tested and why** → [docs/testing-strategy.md](docs/testing-strategy.md).
- **New routes and URL rules** → [docs/urls.md](docs/urls.md).
- **Words in the UI, emails, and PDFs** → [docs/writing.md](docs/writing.md).

Recurring maintenance prompts for agents are in
[agent_prompts/](agent_prompts/README.md).

For general technique, prefer the upstream docs over bundled guides:

- [Phoenix](https://hexdocs.pm/phoenix), [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view),
  and [Ecto](https://hexdocs.pm/ecto).
- [Elixir](https://hexdocs.pm/elixir) and [Oban](https://hexdocs.pm/oban).
- [D4H API access keys](https://help.d4h.com/article/377-obtaining-an-api-access-key).
