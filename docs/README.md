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
team's system of record. Oban jobs copy each team's members, activities, attendance,
qualifications, and groups from the D4H API into a local SQLite database, syncing what
changed every 10 minutes, and the pages read from that copy. A team without D4H keeps
its records in SAR Duty Records, which serves the same API. On top of it the app builds
what D4H doesn't: tax credit letters as PDFs, mileage reports, attendance cleanup, and
group qualification rules. It runs as one Fly machine with Litestream replicating the
database.

## The layers and the calling rules

| Layer       | Path                                  | Responsibility                                        | May call                                                 |
| ----------- | ------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------- |
| Web         | `lib/web/`                            | LiveViews, controllers, components                    | Operations, models, view models/data, workers' `enqueue` |
| Operations  | `lib/app/operation/`                  | Side effects and orchestration, `call/…`              | Adapters, models, other operations                       |
| Workers     | `lib/app/worker/`                     | Oban jobs; schedule and run operations                | Operations, models                                       |
| Adapters    | `lib/app/adapter/`                    | One external API each; map responses to structs       | `Req`                                                    |
| Models      | `lib/app/model/`, `lib/app/accounts/` | Ecto schemas and their queries                        | `Repo`, fields, validators                               |
| View models | `lib/app/view_model/`                 | Embedded schemas that validate filter and form params | Models                                                   |
| View data   | `lib/app/view_data/`                  | Read-only query bundles for one page                  | Models                                                   |
| MCP tools   | `lib/app/mcp/`                        | Views of a team's data for agents, and proposals      | Models, operations                                       |
| Service     | `lib/service/`                        | Stateless helpers: formatting, conversion, PDF        | — (no `Repo`, no HTTP)                                   |

The rules that are easy to break:

- **Only adapters know about upstream.** A D4H URL, query parameter, or JSON field name
  outside `lib/app/adapter/` is a bug.
- **LiveViews don't perform side effects directly.** A `handle_event` calls an Operation;
  the Operation talks to D4H, Mapbox, or the mailer. `ActivityMileageLive` predates
  this rule and calls the D4H adapter directly.
- **Every team query is scoped by `team_id`**, including joins, and a record is found
  through the current team before it is changed or deleted.
- **Local ids and D4H ids never mix.** Foreign keys are local; `d4h_*_id` columns hold
  D4H's ids and are what the adapter takes.

## Where rules live

A rule is code that decides what may happen or what is true: a guard, an eligibility
check, or a value that gets saved or sent. Each rule has one home, so every page, job,
and MCP tool that needs it gets the same answer.

- **A rule about one action** lives in the operation every entry point calls, as a pure
  function the tests call directly: `SetGroupMember.check_keeps_a_team_admin/4`,
  `ReplyToActivity.plan/4`. A guard on one page alone is skipped by the others: the
  last-admin check once sat only on the Standing tab, and the group pages and the bulk
  add went around it (#683).
- **A definition many places share** (attended, counted, current, open) lives on its
  model as a query and a pure predicate: `Attendance.attended/2`, `Member.counted?/2`,
  `Activity.open?/2`. A source test keeps copies out when one is easy to rewrite by hand.
- **A page may ask the same function** to hide a button or explain a refusal, never its
  own copy. The operation checks again when it runs.
- **Views keep what to show and how**: wording, layout, and filtering rows already
  loaded. Read bundles for a page go in view data, and a view data module may hold a
  pure rule when only reading needs it, like `TeamAttention`, which the dashboard and
  the MCP tool share.

A guard that must read inside the write's transaction, like a chore a team admin may
have decided since the page loaded, stays in `call`.

## Where do I put new code?

- **New page** → a LiveView in `lib/web/live/`, with `use Web, :live_view_app_layout` for
  team, member, and admin pages, `:live_view_narrow_layout` for one task done with a
  phone or iPad in hand (logging in, an activity's scanner, scanning kit; see
  `/styles/layout`),
  or `:live_view_marketing_layout` for public pages. A page in the side navigation
  is a line in `Web.Navigation` ([navigation.md](navigation.md)). Add the route in `lib/web/router.ex`
  inside the `live_session` whose `on_mount` checks what the page needs (signed in, admin,
  or a member of the team in the URL).
- **New filterable list** → a view model in `lib/app/view_model/` with
  `use App, :view_model`: an embedded schema for the filters and a `validate/1` that
  returns `{:ok, options, changeset}`. The LiveView calls it in `handle_params/3`, assigns
  `to_form(changeset, as: "form")`, pages with `Repo.paginate/2` (an `App.Page`), keeps filters
  in the URL with `push_patch`, and raises `Web.Status.NotFound` on invalid params.
  [TaxCreditLetterFilterViewModel](../lib/app/view_model/tax_credit_letter_filter_view_model.ex)
  is the fullest example.
- **New table or column** → `mix ecto.gen.migration name`, then a schema in
  `lib/app/model/` with `use App, :model`. Use `App.Field.TrimmedString` for user-entered
  text, `App.Field.EncryptedString` for credentials, and the `App.Validate` helpers in
  the changeset. Add a fixture to `test/support/fixtures/app_fixtures.ex` when a test
  needs the row.
- **New D4H data** → a struct in `lib/app/adapter/d4h/` with `build/1`, a fetch function
  in `lib/app/adapter/d4h.ex`, and — if it is stored — an upsert stage in
  `lib/app/operation/refresh_d4h_data/`. See [d4h-sync.md](d4h-sync.md).
- **New side effect** → an Operation in `lib/app/operation/`. If it has logic worth
  testing, give it a pure function and test that; see
  [testing-strategy.md](testing-strategy.md).
- **New background work** → a worker in `lib/app/worker/` with an `enqueue` function. See
  [jobs.md](jobs.md) for whether it should be a job at all.
- **New shared UI** → a function component in `lib/web/components/`: `core.ex` for the
  pieces every page uses, or its own module. Every LiveView layout imports the same shared
  modules (`live_view/1` in `lib/web.ex`); a component only one or two pages use is
  imported by those pages. Icons are `<.icon name="…">`, Lucide's, copied in with `bin/icons`. Styling is the design system at
  `/styles`: components and classes first, Tailwind utilities on its scale for one-off
  layout (AGENTS.md has the rules).
- **New MCP tool** → a module in `lib/app/mcp/tool/` with the `App.MCP.Tool` behaviour,
  listed in `App.MCP.Tools`. See [mcp.md](mcp.md).
- **New displayed value** → a function in `Service.Format`, not arithmetic in a template.

## The docs

- [d4h-sync.md](d4h-sync.md) — how D4H data reaches the database, and what is never deleted.
- [change-sets.md](change-sets.md) — how every write to D4H goes through one applier, and what it records.
- [records.md](records.md) — teams without D4H: SAR Duty Records as a second service, and how a team connects.
- [change-history.md](change-history.md) — each member's and activity's history: SAR Duty's writes and what the refresh saw change in D4H.
- [equipment.md](equipment.md) — equipment from D4H, and adding equipment to an activity.
- [chores.md](chores.md) — chores: members log them, team admins accept them, and SAR Duty sends them to D4H.
- [certificates.md](certificates.md) — certificates: members send them, team admins accept them into D4H as awards.
- [custom-fields.md](custom-fields.md) — D4H's custom fields: what is copied, how fresh it is, and why restricted fields never reach an organisation.
- [templates.md](templates.md) — templates: items, tags, and groups whose members they add, applied to an activity in one step.
- [group-rules.md](group-rules.md) — qualification rules for groups: storage, evaluation, and what applying them needs.
- [member-cards.md](member-cards.md) — member ID cards and the public verify site.
- [needs-attention.md](needs-attention.md) — the team home's Needs attention list: adding an item, and which can be snoozed.
- [members.md](members.md) — the members list and its filters, and member logins: members get their own ID card and tax credit letters.
- [tax-credit-letters.md](tax-credit-letters.md) — verifying a tax credit letter, its reference numbers, and the locked PDF.
- [urls.md](urls.md) — how paths are named, and the URLs that can never move.
- [navigation.md](navigation.md) — areas, the side navigation, and the account menu that switches between them.
- [search.md](search.md) — the top bar's search: what it matches, how it ranks, and who finds what.
- [mcp.md](mcp.md) — the MCP endpoint trial: tokens, the read-only tools, and the call log.
- [taking-attendance.md](taking-attendance.md) — Take attendance: who scans ID cards at an activity and when, the times they record, and sending them to D4H.
- [sar-command-assist.md](sar-command-assist.md) — SAR Command Assist, the incident tool many teams run beside SAR Duty, and where the two meet.
- [organizations.md](organizations.md) — parent organizations like BCSARA, their branding, and giving one its own verify host.
- [jobs.md](jobs.md) — background jobs: when work is a job, how one is shaped, and how it reports a failure.
- [external-services.md](external-services.md) — every third-party boundary, its credentials, and what breaks without it.
- [deployment.md](deployment.md) — Fly, Litestream, migrations, backups, and changing production data.
- [testing-strategy.md](testing-strategy.md) — what the test suite covers and why.
- [writing.md](writing.md) — the rules and glossary for every word a person reads in the app.
- [mockups.md](mockups.md) — how a design proposal is drawn: real pages, fuchsia marks,
  numbered pins.
- [history.md](history.md) — the project's story log, in place of a changelog.

Recurring maintenance prompts for AI agents live in
[agent_prompts/](../agent_prompts/README.md).

## Conventions

- This folder is flat — add a new `*.md` here; don't introduce subfolders unless a topic
  genuinely needs several files.
- Prefer linking to source files over describing them.
- Keep docs short. A doc that outgrows ~1.5 screens is probably narrating code.
- Docs are spell-checked and linted: run `mise run check`.
