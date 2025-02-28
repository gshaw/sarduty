# SAR Duty

Helpful tools for search and rescue managers

## Setup

```sh
brew install mise flyctl puma-dev
puma-dev -install
cp .mise.example.toml .mise.local.toml
# Add MAPBOX_ACCESS_TOKEN
mise trust
mise install
echo 4025 > ~/.puma-dev/sarduty
```

## Tasks

* `mix setup` to install and setup dependencies
* `mix test` to run tests
* `mix phx.server` to start dev server
* `iex -S mix phx.server` to start dev server inside IEx
* `mise spell .` to run cSpell spell checker
* `mise check .` to run all checks (use before git push or deploy)
* `fly deploy` to deploy current version

## Troubleshooting

Restarting my Mac fixed an issue with puma-dev not server the app correctly.
