# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sarduty,
  ecto_repos: [App.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :sarduty, Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Web.ErrorHTML, json: Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: App.PubSub,
  # cspell:ignore VdFiDhpc
  live_view: [signing_salt: "VdFiDhpc"]

config :sarduty, App.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      iv_length: 12,
      key: Base.decode64!("D7Lfe2YebDGeefH/D6C0oBasmaWM8iu8FkF0mMTwe9g=")
      # 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
      # https://hexdocs.pm/cloak_ecto/install.html
    }
  ]

# Configure mailer for dev and test
config :swoosh, local: true
config :sarduty, App.Mailer, adapter: Swoosh.Adapters.Local

# Configure Timezone database: https://github.com/lau/tzdata
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure Phoenix to filter sensitive parameters
config :phoenix, :filter_parameters, ["access_key"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
