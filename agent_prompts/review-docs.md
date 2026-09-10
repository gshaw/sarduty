# Review and update the project docs

_Run monthly, or after a subsystem changes substantially. Updates the living docs:
`docs/*.md`, root `README.md`, and `AGENTS.md`._

You are auditing this repo's documentation for **drift against the code** and fixing what's
stale. This is a freshness and accuracy pass, not a rewrite — keep changes surgical, and
flag (don't silently rewrite) anything that looks substantially wrong.

## Scope

**In scope** — the living reference docs:

- `docs/README.md`, `docs/d4h-sync.md`, `docs/group-rules.md`,
  `docs/external-services.md`, `docs/deployment.md`
- root `README.md`
- `AGENTS.md`

**Out of scope — do not edit:**

- `docs/history.md` — maintained by `refresh-history.md`.
- `docs/testing-strategy.md` — owned by `review-tests.md`.
- `agent_prompts/*` — these prompts.
- `CLAUDE.md` — just an `@AGENTS.md` import; nothing to review.

## What to check, per doc

1. **Claims match the code.** For each concrete reference — a file path, module, function,
   environment variable, route, Oban queue or cron, layer rule — confirm it still exists
   and still does what the doc says. Use `grep` and file reads to spot-check the
   load-bearing claims, especially anything describing a flow, an invariant, or a
   boundary to an external service. A renamed module or a moved file is the most common
   rot.
2. **Claims worth re-verifying every run:**
   - **What the D4H sync deletes.** `docs/d4h-sync.md` says only attendance is deleted.
     Grep `lib/app/operation/refresh_d4h_data/` for `delete` and `delete_all`. If another
     stage now deletes stale rows, update the doc and `docs/group-rules.md`.
   - **The sync stages** listed in `docs/d4h-sync.md` against the stage names in
     `lib/app/operation/refresh_d4h_data.ex` and `@refresh_stages` in
     `lib/web/live/team_dashboard_live.ex`.
   - **Which LiveViews call D4H directly.** `AGENTS.md` and `docs/README.md` name
     `ActivityAttendanceLive`, `ActivityMileageLive`, and `Settings.TeamLive`. Grep
     `lib/web/` for `D4H.` and `build_context`; add any new offender and drop any that has
     moved to an Operation.
   - **Environment variables.** Every `System.get_env` and `System.fetch_env!` in
     `config/` and `lib/` appears in `docs/external-services.md`, and nothing listed there
     is gone. Check `.mise.example.toml` lists the ones needed locally.
   - **Generator boilerplate hasn't crept back.** A Phoenix upgrade or `usage_rules` can
     re-insert `<!-- usage-rules-start -->` blocks or "Phoenix v1.8 guidelines" into
     `AGENTS.md`. Remove them; the Phoenix hazards section in `AGENTS.md` is the
     deliberate short version.
3. **Outbound links resolve.** Every markdown link inside the in-scope docs — to a source
   file or another doc — points at something that exists. Fix or drop dead links.
4. **Inbound links still resolve.** Grep the whole repo for references to doc filenames —
   root `README.md`, `AGENTS.md`, other `docs/*.md`, `agent_prompts/*`, and code comments
   — and fix any that point at a doc that has moved or been deleted.
5. **The docs index is complete.** `docs/README.md`'s "The docs" list matches the actual
   set of `*.md` in `docs/` — nothing added-but-unlisted, nothing listed-but-deleted.
6. **House style (from `docs/README.md`).** Code is documentation: docs should not restate
   what the code shows directly. Prefer linking to source over describing it. A doc past
   ~1.5 screens is probably narrating code; flag it. The folder is flat.

## How to work

- Go doc by doc. For each, list what you verified, what you changed, and what looked stale
  but you left for a human (with the reason).
- Make the smallest edit that restores accuracy. Don't reformat untouched prose, don't
  expand scope, don't invent detail the code doesn't support.
- If a whole doc has drifted badly (its subsystem was rewritten), say so plainly rather
  than patching line by line — propose what it should cover and ask before rewriting.
- Run `mise run check` and resolve anything it flags. Add genuine proper nouns to
  `.cspell.yaml` only when they recur across files; otherwise use an inline
  `<!-- cspell:ignore … -->`.

Then show me the diff before saving anything, and give me a short per-doc summary: verified
clean / edited (what) / flagged (what and why).

Finally, log the run: prepend an entry to `agent_prompts/worklog.md`
(`## <today> — review-docs` then a one-line summary), included in the same change.

If `run-scheduled.md` is driving this run, stop after the edits and the worklog entry — it
handles the branch, commit, and PR. Run standalone, leave committing to me.
