# Agent task worklog

A running record of when the maintenance prompts in this folder were last run and what they
changed. Each prompt appends its own entry as its final step; the
[`run-scheduled`](run-scheduled.md) orchestrator reads this file to decide what's due.

Format: newest entry first, one per run.

```txt
## YYYY-MM-DD — <prompt-name>
One-line summary of what changed (or "no changes needed"). (commit <short-sha>, if committed)
```

---

<!-- New entries go directly below this line, newest first. -->

## 2026-10-23 — refresh-history

Added late October for the 146 commits since 39e3370: members' own space and view as
member, equipment and templates, chores, replies and reminders, hours tags per team,
standing and the new group rules, the side navigation, filter bar, stat switch, and
search, and the SQLite lock fix. The year is now "Many teams, members, and the door".

## 2026-10-23 — review-tests

Every route and event added since 2026-10-09 that takes an id looks it up through the
team; no new P0 hole. Added tests that the sync's attendance deletes (month and activity
fetches, which letter hours rest on) and equipment deletes never reach another team's
rows; the attendance one fails when the team filter is removed. Fixed two warnings in
test files, and `mise run test` now fails on them. Left: `GroupRules.flip_warning/3` is
pure and untested (P2). 1544 passed.

## 2026-10-23 — review-docs

Every link, module, function, and path the docs name exists (checked by script). Fixed:
the sync's delete list lacked equipment items and usages, d4h-sync still named the
removed attendance import, the narrow layout is for any hand-held task, a lone team's
one-team organization gave way to its own hours tags (#323), the release's env vars
are listed, `.mise.example.toml` gains `HEALTHCHECKS_SYNC_URL` and `RECORDS_HOST`, and
AGENTS.md's workers include tax credit letters. Flagged: migrations run twice outside a
release (`App.Release.migrate/0` and the `Ecto.Migrator` child).

## 2026-10-23 — review-deps

Hex packages were already current from #502. Bumped Erlang 29.0.6 → 29.1.2 (builder
image `1.20.4-erlang-29.1.2-debian-trixie-20261020-slim`, runner `trixie-20261020-slim`),
Node 26.12.1, cspell 10.4.0, prettier 3.9.10, markdownlint-cli2 0.24.0. Reported, not
changed: `mix hex.audit` flags Cloak 1.1.4 for CVE-2026-95105 (AES-CTR has no
authentication); the vault uses only AES-GCM, so SAR Duty is not affected and there is no
fixed Cloak release yet. Litestream 0.5.17 is the latest.

## 2026-10-09 — refresh-history

Added September and October 2026 for the ~150 commits since f9ca9e8: ID cards and
Wallet passes, self sign-up with D4H access, the 10-minute sync and change history,
change sets, attendance at the door, letter verification, the MCP trial, the design
system, and SAR Duty Records.

## 2026-10-09 — review-tests

Fixed two P1 bugs and tested them: a Records edit was recorded twice in history, the
second time as "Someone in D4H", and one route Mapbox couldn't find crashed the whole
mileage report. The mileage arithmetic is now a pure `BuildMileageReport.build/3`.
Deleted `page_controller_test` (its controller is gone) and the refresh worker's
`assert true`. Team scoping held everywhere checked. 891 passed.

## 2026-10-09 — review-docs

Fixed drift in AGENTS.md and nine docs: the daily refresh is a 10-minute sync, login is
an emailed or texted code (the old link section is gone), Records edits are writes, MCP
proposals are the one write, both Healthchecks URLs, the door's phone numbers (#245),
and letters no longer email from a `Task.start`.
