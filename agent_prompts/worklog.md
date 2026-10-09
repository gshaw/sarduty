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
