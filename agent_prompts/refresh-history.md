# Refresh the development history

_Run quarterly, or whenever the current year's section feels out of date. Updates
`docs/history.md`._

You are updating `docs/history.md` — a high-level development history with one section
per year (`## YYYY — <theme>`), **most recent year first**, and bullets within a year
**most recent month first**. Bring it up to date.

1. **Find the cutoff.** Read the `Last updated:` line at the bottom of `docs/history.md` —
   it names the date and commit SHA the history currently covers.

2. **Survey new history.** Run:

   ```sh
   git log --reverse --format="%ad|%s" --date=short <LAST_SHA>..HEAD
   ```

   Replace `<LAST_SHA>` with the SHA from the footer. Merged PRs show up as `(#NN)` in the
   subject; `gh pr list --state merged --limit 30` gives their titles if the subjects are
   thin.

3. **Distill, don't transcribe.** Ignore noise: dependency bumps, formatting, lint and
   spelling fixes, "fix warnings", pure renames, merge commits, and tiny tweaks. Group what
   remains by theme — a feature area or a cluster of fixes — not by commit. If a feature
   took many commits, state the outcome in one bullet, not the journey.

4. **Slot the work into years and months.**
   - Same year as the top section → add bullets to it, newest month first. Refresh its
     `<theme>` if the additions shift it.
   - A new year has started → add a new `## YYYY — <short theme>` heading at the top.
   - Never reorder or rewrite older sections except to tighten them (see step 6).

5. **Match the voice.** Past tense, terse, written for a SAR team manager as much as a
   developer: say what a team could now do, not which module changed. Bold the month at
   the start of each bullet. Reference notable PRs and issues as `(#NN)`.

6. **Keep it small.** The whole document should stay skimmable in a couple of minutes. If
   it's growing long, tighten the oldest years. Detail belongs in git history, not here.

7. **Update the footer.** Set the `Last updated:` line to today's date and the new HEAD SHA
   (`git rev-parse --short HEAD`).

Then show me the diff before saving anything, and tell me the one or two most notable
changes since last time.

Finally, log the run: prepend an entry to `agent_prompts/worklog.md`
(`## <today> — refresh-history` then a one-line summary), included in the same change.

If `run-scheduled.md` is driving this run, stop after the edits and the worklog entry — it
handles the branch, commit, and PR. Run standalone, leave committing to me.
