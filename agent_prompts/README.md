# Agent prompts

Standalone prompts for recurring maintenance an AI agent (Claude Code or similar) can run
to keep the repo tidy. Each prompt is its own `.md` file so it's easy to copy whole or hand
to an agent directly — nothing here runs automatically.

## Run everything that's due

**Do this monthly.** Start a Claude Code session in the repo root and tell the agent
**`Run the prompt in agent_prompts/run-scheduled.md`**. It reads the cadence table below and
the [worklog](worklog.md), works out which prompts are due, runs them — asking you to
confirm first — and bundles everything into one dated PR (`scheduled-<YYYY-MM>`), one
commit per task. Running it monthly covers the monthly tasks and picks up the quarterly
ones whenever their turn comes around.

## How to run one

- **In Claude Code:** `Run the prompt in agent_prompts/<file>.md` — the agent reads and
  follows it.
- **By hand:** open the file, select all, paste into your agent. The entire file body _is_
  the prompt; there's no surrounding commentary to strip out.

Review the diff the agent proposes before committing — these are starting points, not
unattended jobs.

## Available prompts

| Prompt                                   | Cadence   | Updates                                                 |
| ---------------------------------------- | --------- | ------------------------------------------------------- |
| [review-deps.md](review-deps.md)         | Monthly   | `mix.exs`, `mix.lock`, `.mise.toml`, `Dockerfile`       |
| [review-docs.md](review-docs.md)         | Monthly   | Living docs: `docs/*.md`, root `README.md`, `AGENTS.md` |
| [review-tests.md](review-tests.md)       | Monthly   | `test/`, pure functions in `lib/`                       |
| [refresh-history.md](refresh-history.md) | Quarterly | `docs/history.md`                                       |

Each prompt records its run in [worklog.md](worklog.md) (newest first) as its final step;
that's how `run-scheduled` knows when each task last ran. [run-scheduled.md](run-scheduled.md)
is the orchestrator, not a scheduled task itself — it has no cadence and doesn't log.

## Adding a prompt

1. Create `agent_prompts/<name>.md`. The whole file is the prompt — write it as direct
   instructions (a title, a one-line context note, then numbered steps). No blockquotes,
   no wrapper prose, so it stays copy-pasteable.
2. Tell the agent exactly what to read, how to decide what matters, where to write, and to
   show a diff before saving.
3. End the prompt with a step that prepends a one-line entry to [worklog.md](worklog.md)
   (`## <today> — <name>`), so `run-scheduled` can track its cadence.
4. Add a row to the **Available prompts** table above.
