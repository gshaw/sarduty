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

# Configure Oban
config :sarduty, Oban,
  engine: Oban.Engines.Lite,
  repo: App.Repo,
  queues: [default: 5, refresh: 1],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 6 * * *", App.Worker.ScheduleTeamRefreshesWorker}
     ]}
  ]

# Setting this replaces Phoenix's default of ["password"], so list it too. Each entry
# matches any param name that contains it: "token" covers the confirm and reset links.
config :phoenix, :filter_parameters, ["password", "access_key", "token"]

# Honeybadger reports errors, and Insights sends request, query, and job timings. It
# sends nothing in dev or test, or without HONEYBADGER_API_KEY. Its filter_keys match
# whole key names, not substrings like the list above, so each variant is listed;
# http_cookie drops the session cookie from the request headers. filter_args keeps
# function arguments, which can be members, out of backtraces.
config :honeybadger,
  app: :sarduty,
  environment_name: config_env(),
  insights_enabled: true,
  use_logger: true,
  ecto_repos: [App.Repo],
  filter: Web.HoneybadgerFilter,
  filter_args: true,
  filter_keys: [
    :password,
    :current_password,
    :password_confirmation,
    :access_key,
    :token,
    :http_cookie,
    :__changed__,
    :flash,
    :_csrf_token
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
