# SAR Duty

Helpful tools for search and rescue managers

## Setup

```sh
cp .mise.example.toml .mise.local.toml
# Add MAPBOX_ACCESS_TOKEN
mise trust
echo 4025 > ~/.puma-dev/sarduty
```

## Tasks

* `mise install` to install Erlang and Elixir
* `mix setup` to install and setup dependencies
* `mix test` to run tests
* `mix phx.server` to start dev server
* `iex -S mix phx.server` to start dev server inside IEx
* `fly deploy` to deploy current version

## Troubleshooting

Restarting my mac fixed an issue with puma-dev not server the app correctly.
