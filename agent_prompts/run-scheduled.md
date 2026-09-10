# Run the scheduled agent tasks

_The single entry point — "go do the scheduled agent things." Works out which maintenance
prompts in this folder are due, runs them, and bundles the result into one PR._

1. **Read the schedule.** The "Available prompts" table in `agent_prompts/README.md` lists
   each prompt file and its cadence (monthly / quarterly).

2. **Read the worklog.** `agent_prompts/worklog.md` records past runs, newest first. For
   each prompt, find its most recent entry to get the date it last ran. No entry → it has
   never run → treat it as due.

3. **Decide what's due.** A task is due when today's date minus its last-run date meets or
   exceeds its cadence (monthly ≈ 30 days, quarterly ≈ 90). Don't be rigid — if it's
   clearly that time of the month or quarter, run it. List what you'll run and what you'll
   skip (with each task's last-run date), and let me confirm before doing anything. **If
   nothing is due, stop here — no branch, no PR.**

4. **Make a branch for the run.** Start from a clean working tree on an up-to-date `main`
   (`git switch main && git pull`). Create one branch for the whole sweep:
   `git switch -c scheduled-<YYYY-MM>` (if that branch already exists, add a suffix:
   `scheduled-<YYYY-MM>-2`, `-3`, …). Everything below happens on this branch. The name is
   flat and slash-free on purpose — `AGENTS.md` forbids path prefixes in branch names.

5. **Run each due task in table order** by following its prompt file. Each prompt makes its
   edits, shows its diff for your approval, and appends its own worklog entry — let it do
   that. Then **commit that task's changes on its own**, so the history reads by area:
   `Scheduled: <prompt-name> — <one-line summary>`. Move to the next task. Tasks are
   independent; if one stalls or needs a decision, park it (don't commit a half-done task),
   note it, and continue the others.

6. **Open one PR.** When the due tasks are committed, run `mise run ci` and fix anything it
   flags. Then push the branch and open a single PR with `gh`:
   - Title: `Scheduled maintenance — <YYYY-MM>`.
   - Body: one short section per task that ran (lift the summaries from the worklog
     entries), plus a note of anything skipped as not-yet-due or parked.

7. **Summarize.** Give me the PR link and a one-line recap: which tasks ran, which were
   skipped, anything parked.

This orchestrator is not itself a scheduled task — don't log a worklog entry for it.
