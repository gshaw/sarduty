# SAR Duty Docs

The map of how the app is built — read this before changing a subsystem. These docs are
reviewed like code and are meant to orient both humans and AI agents.

## Principle: code is documentation

We do not document what can be read directly from the code. Schemas, function lists, and
straightforward LiveView code are not restated here. These docs capture only what code
cannot easily show: the layering and where things live, the non-obvious invariants and
hazards, and the flows that cross modules. When in doubt, link to the source instead of
describing it.

## The app in one paragraph

SAR Duty is a Phoenix LiveView app for search and rescue team managers. D4H is each
team's system of record. A daily Oban job copies each team's members, activities,
attendance, qualifications, and groups from the D4H API into a local SQLite database, and
the pages read from that copy. On top of it the app builds what D4H doesn't: tax credit
letters as PDFs, mileage reports, attendance cleanup, group qualification rules, and a
read-only MCP endpoint. It runs as one Fly machine with Litestream replicating the
database.

## The layers and the calling rules

| Layer       | Path                                  | Responsibility                                        | May call                             |
| ----------- | ------------------------------------- | ----------------------------------------------------- | ------------------------------------ |
| Web         | `lib/web/`                            | LiveViews, controllers, components                    | Operations, models, view models/data |
| Operations  | `lib/app/operation/`                  | Side effects and orchestration, `call/…`              | Adapters, models, other operations   |
| Workers     | `lib/app/worker/`                     | Oban jobs; schedule and run operations                | Operations, models                   |
| Adapters    | `lib/app/adapter/`                    | One external API each; map responses to structs       | `Req`                                |
| Models      | `lib/app/model/`, `lib/app/accounts/` | Ecto schemas and their queries                        | `Repo`, fields, validators           |
| View models | `lib/app/view_model/`                 | Embedded schemas that validate filter and form params | Models                               |
| View data   | `lib/app/view_data/`                  | Read-only query bundles for one page                  | Models                               |
| Service     | `lib/service/`                        | Stateless helpers: formatting, conversion, PDF        | — (no `Repo`, no HTTP)               |

The rules that are easy to break:

- **Only adapters know about upstream.** A D4H URL, query parameter, or JSON field name
  outside `lib/app/adapter/` is a bug.
- **LiveViews don't perform side effects directly.** A `handle_event` calls an Operation;
  the Operation talks to D4H, Mapbox, or the mailer. `ActivityAttendanceLive`,
  `ActivityMileageLive`, and `Settings.TeamLive` predate this rule and call the D4H
  adapter directly.
- **Every team query is scoped by `team_id`**, including joins, and a record is found
  through the current team before it is changed or deleted.
- **Local ids and D4H ids never mix.** Foreign keys are local; `d4h_*_id` columns hold
  D4H's ids and are what the adapter takes.

## Where do I put new code?

- **New page** → a LiveView in `lib/web/live/`, with `use Web, :live_view_app_layout` for
  team pages, `:live_view_narrow_layout` for auth and settings forms, or
  `:live_view_marketing_layout` for public pages. Add the route in `lib/web/router.ex`
  inside the `live_session` whose `on_mount` checks what the page needs (signed in, admin,
  or a member of the team in the URL).
- **New filterable list** → a view model in `lib/app/view_model/` with
  `use App, :view_model`: an embedded schema for the filters and a `validate/1` that
  returns `{:ok, options, changeset}`. The LiveView calls it in `handle_params/3`, assigns
  `to_form(changeset, as: "form")`, pages with `Repo.paginate/2` (Scrivener), keeps filters
  in the URL with `push_patch`, and raises `Web.Status.NotFound` on invalid params.
  [TaxCreditLetterFilterViewModel](../lib/app/view_model/tax_credit_letter_filter_view_model.ex)
  is the fullest example.
- **New table or column** → `mix ecto.gen.migration name`, then a schema in
  `lib/app/model/` with `use App, :model`. Use `App.Field.TrimmedString` for user-entered
  text, `App.Field.EncryptedString` for personal data, and the `App.Validate` helpers in
  the changeset. Add a fixture to `test/support/fixtures/app_fixtures.ex` when a test
  needs the row.
- **New D4H data** → a struct in `lib/app/adapter/d4h/` with `build/1`, a fetch function
  in `lib/app/adapter/d4h.ex`, and — if it is stored — an upsert stage in
  `lib/app/operation/refresh_d4h_data/`. See [d4h-sync.md](d4h-sync.md).
- **New side effect** → an Operation in `lib/app/operation/`. If it has logic worth
  testing, give it a pure function and test that; see
  [testing-strategy.md](testing-strategy.md).
- **New shared UI** → a function component in `lib/web/components/` (`core.ex` for form
  primitives, `ui.ex` for app-wide pieces). Import it in the layout macro in `lib/web.ex`
  that needs it. Icons are `<.icon name="hero-…">`; styling is Tailwind utilities with no
  `@apply` and no UI kit.
- **New displayed value** → a function in `Service.Format`, not arithmetic in a template.

## The docs

- [d4h-sync.md](d4h-sync.md) — how D4H data reaches the database, and what is never deleted.
- [group-rules.md](group-rules.md) — qualification rules for groups: storage, evaluation, and what applying them needs.
- [external-services.md](external-services.md) — every third-party boundary, its credentials, and what breaks without it.
- [deployment.md](deployment.md) — Fly, Litestream, migrations, backups, and changing production data.
- [testing-strategy.md](testing-strategy.md) — what the test suite covers and why.
- [history.md](history.md) — the project's story log, in place of a changelog.

Recurring maintenance prompts for AI agents live in
[agent_prompts/](../agent_prompts/README.md).

## Conventions

- This folder is flat — add a new `*.md` here; don't introduce subfolders unless a topic
  genuinely needs several files.
- Prefer linking to source files over describing them.
- Keep docs short. A doc that outgrows ~1.5 screens is probably narrating code.
- Docs are spell-checked and linted: run `mise run check`.
