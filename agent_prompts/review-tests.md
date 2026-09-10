# Review the test suite for holes

_Run monthly, or after a major feature lands. May add files under `test/`, extract pure
functions from Operations in `lib/`, and update `docs/testing-strategy.md`._

You are looking for **obvious, high-consequence gaps** in the test suite, judged against
the project's own testing strategy — not chasing coverage. The deliverable is a prioritized
gap report; implementing the top gaps is a follow-up the human approves.

## Ground yourself in the strategy first

Read `docs/testing-strategy.md` in full. It is the rubric. In particular:

- The **principles** (test intent not implementation, no tautologies, pure functions
  first, edges over happy paths, deterministic). Any test you propose must satisfy these.
- The **"What we deliberately do not test"** list (HEEx markup and styling, Ecto
  round-trips, generated auth behaviour, third-party libraries, live D4H or Mapbox).
  **Never flag these as holes.**
- The **High-value targets** table and the **Known gaps** section — start by deciding
  whether they are still the right next tests.

## Find the holes

1. **Inventory.** List the test files under `test/` (they mirror `lib/`) and, from the
   strategy, which targets they satisfy. Note placeholders (`assert true`).
2. **Untested targets.** Surface any high-value target from the strategy that has no test
   yet.
3. **New untested logic.** Scan for logic added since the strategy was last updated
   (`git log --since=<last review-tests date> --stat -- lib/`). In this codebase that
   means: new Operations under `lib/app/operation/`, new upsert stages under
   `lib/app/operation/refresh_d4h_data/`, D4H `build/1` functions and
   `App.Adapter.D4H.Parse`, view model `validate/1` and filter scopes, model query
   functions that compute a number a user sees (hours, counts), and `Service.*` helpers.
4. **Logic trapped in the shell.** An Operation or LiveView whose `call` or
   `handle_event` does real work inline — a filter, a sum, a set difference, a date
   boundary — next to `Repo` or HTTP calls is untestable by the project's own rules. Flag
   the extraction into a pure function, not just the missing test.
5. **Team scoping.** For each LiveView, controller action, and MCP tool that takes an id
   from the client, check that the record is looked up through the current team. A missing
   check is a P0 gap even if nothing has gone wrong yet.

For every candidate, write: the **behaviour a team manager cares about**, why a regression
would be **silent and costly**, where the **logic lives** (file and function), and
whether it first needs a pure function extracted to be testable.

Rank everything P0 (a wrong number on a tax credit letter, wrong group membership, one team
seeing or changing another's data) → P1 (correctness users notice) → P2 (useful, lower
consequence). Drop anything that only earns a tautological or implementation-mirroring
test.

## Traps specific to this suite

- **Never call D4H or Mapbox.** Oban runs with `testing: :inline`, so a test that clicks a
  refresh button runs the real worker against the live API. Test the pure function
  instead, or add the `Req.Test` seam described in the strategy first.
- **Don't invent D4H JSON.** A fixture that stands for D4H's response format must come
  from D4H — a captured response with personal details replaced, or the API docs — and the
  report should say which. Invented JSON only proves the parser agrees with its author.
- **Expected numbers come from the inputs, not the code.** For letter hours, build
  attendance fixtures whose minutes you chose, and assert the total you can add up by hand.

## Then, on approval

Implement the highest-value gaps, top-down. Follow the strategy's principles exactly:
assert intent, cover the dangerous edges, keep tests deterministic, pass `now` in rather
than reading the clock, and prefer `use ExUnit.Case, async: true` on a pure function over
`App.DataCase`. Put each test in the path mirroring its source file
(`lib/app/operation/x.ex` → `test/app/operation/x_test.exs`). Update
`docs/testing-strategy.md` if targets change, and note any function you extracted or bug
you found. Run `mise run ci` and make sure it's green.

Show me the gap report first and let me pick what to build. Then show diffs before saving.

Finally, log the run: prepend an entry to `agent_prompts/worklog.md`
(`## <today> — review-tests` then a one-line summary of gaps found / tests added, or
"no changes needed"), included in the same change.

If `run-scheduled.md` is driving this run, stop after the edits and the worklog entry — it
handles the branch, commit, and PR. Run standalone, leave committing to me.
