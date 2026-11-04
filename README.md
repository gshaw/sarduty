# SAR Duty

Helpful tools for search and rescue managers, on top of D4H.

## Setup

```sh
brew install mise flyctl puma-dev
puma-dev -install
cp .mise.example.toml .mise.local.toml
# Add MAPBOX_ACCESS_TOKEN; the rest are optional in dev
mise trust
mise install
mix setup
git config core.hooksPath bin/git-hooks
echo 4025 > ~/.puma-dev/sarduty
```

Then `mise run server` and open <https://sarduty.test>.

## Tasks

- `mise run server` starts the dev server; `iex -S mix phx.server` starts it inside IEx.
  `tools/dev-server.sh` serves a worktree the same way, on the main checkout's database.
- `mix run --no-start tools/dev-sar.exs` adds Dev SAR, the made-up Coast Range cast with
  the site admins as team admins, to try a branch on without touching a real team's data.
  `--reset` seeds it again with today's dates.
- `mise run check` formats, compiles, lints, and spell-checks.
- `mise run test` runs the tests; `mise run ci` runs checks and tests. Run it before
  pushing.
- `git push` first runs CI's static checks, all but the compile, through
  `bin/git-hooks/pre-push`, once `core.hooksPath` is set as in Setup.
  `git push --no-verify` skips them.
- `fly deploy` deploys `main` — see [docs/deployment.md](docs/deployment.md).

How the app is built: [docs/README.md](docs/README.md). Working in this repo as an agent:
[AGENTS.md](AGENTS.md).

## Troubleshooting

Restarting the Mac fixed puma-dev not serving the app.
