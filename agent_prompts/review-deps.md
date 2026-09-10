# Review dependencies and tool versions

_Run monthly. Updates `mix.exs`, `mix.lock`, `.mise.toml`, and the `Dockerfile`._

You are keeping the dependencies current in small, safe steps, and reporting — not doing
— anything that needs a human decision. Phoenix, LiveView, and Oban move quickly; falling
a year behind turns a routine update into a migration project.

## Survey

1. **Hex packages.** Run `mix hex.outdated` and `mix hex.audit` (retired packages). List
   each outdated package with its current and latest version, and whether the update is a
   patch, minor, or major.
2. **Tools.** Run `mise outdated` for the tools pinned in `.mise.toml`.
3. **The Dockerfile must match mise.** The `hexpm/elixir` builder image tag in the
   `Dockerfile` names the Elixir, Erlang, and Debian versions production is built with.
   Check that the Elixir and Erlang versions match `.mise.toml` — a mismatch means CI tests
   one runtime and production runs another. Note the pinned Litestream version too.

## Update

1. **Patch and minor versions** within the constraints in `mix.exs`. Run
   `mix deps.update --all`, then `mix deps.unlock --unused`. For Phoenix, Phoenix
   LiveView, Ecto, and Oban, read the changelog entries between the old and new versions
   and note anything that needs a code change or a deprecation fix.
2. **Tools:** bump patch and minor versions in `.mise.toml`. If Elixir or Erlang changes,
   change the `Dockerfile` image tag to the matching `hexpm/elixir` tag in the same change
   — confirm the tag exists on Docker Hub first.
3. Run `mise run ci`. Fix new compiler warnings and Credo findings the update caused. If
   an update breaks something you can't fix in a few lines, revert that one package and
   report it.

## Report, don't do

- **Major versions** — Phoenix, LiveView, Ecto, Oban, Elixir, Erlang, or anything whose
  changelog says "breaking". List them with a one-line summary of what the upgrade would
  involve, and suggest an issue.
- **Anything retired** by `mix hex.audit`, with the suggested replacement.
- **Deploying.** Never run `fly deploy`. Say that the change needs a deploy to reach
  production.

Show me the survey and the diff before saving anything.

Finally, log the run: prepend an entry to `agent_prompts/worklog.md`
(`## <today> — review-deps` then a one-line summary: what was updated, what was reported),
included in the same change.

If `run-scheduled.md` is driving this run, stop after the edits and the worklog entry — it
handles the branch, commit, and PR. Run standalone, leave committing to me.
