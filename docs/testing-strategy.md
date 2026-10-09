# Testing strategy

What the suite covers, what it deliberately doesn't, and what to add next. The test for
whether a test should exist: would a regression be **silent** and **costly** — a wrong
number on a tax credit letter, the wrong people in a group, one team seeing another's
data?

## Principles

- **Test intent, not implementation.** Assert what a team manager would notice, not how
  the code gets there.
- **No tautologies.** A test that restates the code, or asserts a number only the code
  under test could have produced, proves nothing.
- **Pure functions first.** Logic worth testing lives in a function that takes values and
  returns values, with `now` passed in. Test it with `use ExUnit.Case, async: true`, no
  database. [BuildGroupRulePreview.plan/4](../lib/app/operation/build_group_rule_preview.ex)
  is the reference.
- **Edges over happy paths.** Year boundaries, expired awards, empty inputs, a member from
  another team.
- **Deterministic.** No network, no `DateTime.utc_now()` inside the logic, no order
  dependence.

## What we deliberately do not test

- HEEx markup, layout, and styling.
- Ecto schemas round-tripping through the database, and session handling
  beyond what `accounts_test.exs` and `user_auth_test.exs` already cover.
- Third-party libraries: Oban scheduling, Swoosh delivery, the `pdf` package's output.
- Live D4H or Mapbox responses. **No test may call them.** Oban runs inline in tests, so
  enqueuing a refresh would hit the real API.

## What is covered today

- Accounts and auth: `test/app/accounts_test.exs`, `test/web/user_auth_test.exs`, and the
  `user_*` LiveView tests — the generated suite, kept.
- Group rules: `test/app/operation/build_group_rule_preview_test.exs`, and applying
  them to D4H against a stub: `test/app/operation/apply_group_rule_changes_test.exs`.
- Tax credit letter hours: `test/app/operation/count_tax_credit_hours_test.exs` counts
  each row's own times, merges overlaps (primary wins), and picks the year in the team's
  time zone. The letter list and the letter count the same way
  (`test/app/view_model/tax_credit_letter_filter_view_model_test.exs`).
- Short D4H fetches, which the refresh must never treat as complete:
  `test/app/adapter/d4h/page_test.exs`.
- The refresh deleting rows D4H no longer has, and only the current team's:
  `test/app/operation/refresh_d4h_data/upsert_*_test.exs`.
- The sync every 10 minutes: what it fetches when lists move, and the deletes it finds
  (`test/app/operation/sync_d4h_changes_test.exs`,
  `test/app/worker/sync_team_changes_worker_test.exs`), and the nightly run's Healthchecks
  pings (`finish_run_worker_test.exs`).
- Change sets: `test/app/operation/apply_change_set_test.exs` fails when anything but the
  applier calls a D4H write function, and checks a row D4H changed first is skipped.
- Attendance at the door: the times a send uses (`build_attendance_times_test.exs`), the
  day a typed time lands on (`record_attendance_scan_test.exs`), and what a send plans
  (`send_attendance_to_d4h_test.exs`), never a second row for a member.
- Change history: what the refresh and the sync record, and SAR Duty's own writes not
  recorded twice (`test/app/operation/record_d4h_changes*_test.exs`).
- Records edits: `SaveMember.plan/3` and `SaveActivity.plan/4` name only what changed,
  pure, and the form LiveView tests run each edit against a stubbed Records.
- Mileage round trips: `test/app/operation/build_mileage_report_test.exs`, pure, with
  distances worked out by hand.
- The team dashboard (#205): which activity is NextUp and what Coming up holds
  (`test/app/view_data/team_dashboard_view_data_test.exs`), which "Needs attention" items
  show and in what order (`team_attention_test.exs`), and the year's stats and charts
  (`team_dashboard_charts_test.exs`), all pure.
- Team scoping: `test/web/team_scoping_test.exs` opens another team's record on every
  `/teams/:subdomain/…/:id` route and expects a 404. It fails when a new route of that
  shape is not in its list. `test/web/live/group_live_test.exs` does the same for the rule
  editor's events.
- The MCP endpoint (#28): `test/web/controllers/mcp_controller_test.exs` checks a token
  reads only its own team, that revoked tokens, teams with MCP off, and users who lost
  the D4H bar get 401, and that no tool returns a key outside its `fields/0` or any
  contact detail. Each tool's output is tested pure in `test/app/mcp/`.
- URLs: `test/web/router_test.exs` checks every top-level path against the list in
  [urls.md](urls.md), and that the URLs devices and shared links hold still route.
- Most LiveViews have one smoke test that the page renders or redirects.

## High-value targets

| Target                                           | Why                                           | Shape                             |
| ------------------------------------------------ | --------------------------------------------- | --------------------------------- |
| D4H struct `build/1` and `App.Adapter.D4H.Parse` | A D4H format change corrupts the copy quietly | Pure, against recorded D4H JSON   |

## Known gaps

- **No recorded D4H JSON.** Every D4H request in tests goes to `Req.Test`, and the
  writes, the sync, and Records edits have tests against it. The stubs' JSON is written
  by hand, so the `build/1` functions still need responses recorded from D4H (#33).
- **Fixtures must come from D4H**, not be invented, when they stand for D4H's format —
  otherwise the test only proves the code agrees with itself.
