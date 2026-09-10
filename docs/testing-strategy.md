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
- Ecto schemas round-tripping through the database, and generated `phx.gen.auth`
  behaviour beyond what `accounts_test.exs` already covers.
- Third-party libraries: Oban scheduling, Swoosh delivery, the `pdf` package's output.
- Live D4H or Mapbox responses. **No test may call them.** Oban runs inline in tests, so
  enqueuing a refresh would hit the real API.

## What is covered today

- Accounts and auth: `test/app/accounts_test.exs`, `test/web/user_auth_test.exs`, and the
  `user_*` LiveView tests — the generated suite, kept.
- Group rules: `test/app/operation/build_group_rule_preview_test.exs`.
- Team scoping: `test/web/team_scoping_test.exs` opens another team's record on every
  `/:subdomain/…/:id` route and expects a 404. It fails when a new route of that shape is
  not in its list. `test/web/live/group_live_test.exs` does the same for the rule editor's
  events.
- Most LiveViews have one smoke test that the page renders or redirects.

The two worker tests are `assert true` placeholders.

## High-value targets

| Target                                               | Why                                                 | Shape                                |
| ---------------------------------------------------- | --------------------------------------------------- | ------------------------------------ |
| Letter hours (`Attendance.tagged_minutes_summary/2`) | The number CRA sees. Status, tag, and year filters. | `DataCase` with fixtures             |
| Team scoping in MCP tools                            | One team reading or changing another's data         | `ConnCase`, two teams                |
| D4H struct `build/1` and `App.Adapter.D4H.Parse`     | A D4H format change corrupts the copy quietly       | Pure, against recorded D4H JSON      |
| Stale attendance deletion (`UpsertAttendances`)      | Deletes rows; a wrong set deletes real attendance   | Extract the id arithmetic, test pure |
| Mileage round trips (`BuildMilesageReport`)          | Reimbursement numbers                               | Extract the arithmetic, test pure    |

## Known gaps

- **No HTTP stubbing.** Adapter tests need a seam first: pass a `plug: {Req.Test, …}`
  option through the Req context from test config, so fixtures can stand in for D4H.
- **Letter year uses the UTC date.** `tagged_minutes_summary/2` picks the year with
  `strftime('%Y', started_at)` on UTC, so an activity on the evening of December 31
  Pacific counts toward the next year. A test should pin down which is intended.
- **Fixtures must come from D4H**, not be invented, when they stand for D4H's format —
  otherwise the test only proves the code agrees with itself.
