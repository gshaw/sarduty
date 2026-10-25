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
- `mise run check` formats, compiles, lints, and spell-checks.
- `mise run test` runs the tests; `mise run ci` runs checks and tests. Run it before
  pushing.
- `git push` runs CI's static checks first, through `bin/git-hooks/pre-push`, once
  `core.hooksPath` is set as in Setup. `git push --no-verify` skips them.
- `fly deploy` deploys `main` — see [docs/deployment.md](docs/deployment.md).

How the app is built: [docs/README.md](docs/README.md). Working in this repo as an agent:
[AGENTS.md](AGENTS.md).

## Troubleshooting

Restarting the Mac fixed puma-dev not serving the app.
