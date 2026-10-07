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

# Swoosh's API client is only for its built-in adapters. App.Adapter.CloudflareEmail
# calls Req itself. Its default client needs hackney, which we don't have.
config :swoosh, api_client: false

# Configure mailer for dev and test
config :swoosh, local: true
config :sarduty, App.Mailer, adapter: Swoosh.Adapters.Local

# Configure Timezone database: https://github.com/lau/tzdata
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.28.2",
  default: [
    args:
      ~w(js/app.js --bundle --splitting --format=esm --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
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

# SQLite allows one writer at a time. The SQLite driver's default 2 s wait for the lock lost races
# with syncs, and Oban's job updates failed with "Database busy".
config :sarduty, App.Repo, busy_timeout: 5_000

# Configure Oban
config :sarduty, Oban,
  engine: Oban.Engines.Lite,
  repo: App.Repo,
  # One sync at a time, so two teams' syncs never hold the SQLite write lock together.
  queues: [default: 5, refresh: 1, sync: 1],
  # Lifeline puts back a job left executing by a restart, so it runs again rather than
  # sitting there for good; an hour is far longer than any team's refresh. Pruner keeps a
  # week of finished jobs for looking into a run; events keep the longer history.
  lifeline: [rescue_after: {1, :hour}],
  pruner: [max_age: {7, :days}],
  cron: [
    crontab: [
      {"0 6 * * *", App.Worker.ScheduleTeamRefreshesWorker},
      # The sync every 10 minutes (#163). The nightly full refresh is its safety net.
      {"*/10 * * * *", App.Worker.ScheduleTeamSyncsWorker},
      {"30 5 * * *", App.Worker.PruneEventsWorker}
    ]
  ]

# Setting this replaces Phoenix's default of ["password"], so list it too. Each entry
# matches any param name that contains it: "token" covers attendance links, and "code"
# login, card and short link codes. Paths are filtered by Web.RequestLog.
config :phoenix, :filter_parameters, ["password", "access_key", "token", "code"]

# Honeybadger reports errors, and Insights sends request and job timings. It
# sends nothing in dev or test, or without HONEYBADGER_API_KEY. Its filter_keys match
# whole key names, so Web.HoneybadgerFilter also drops any key containing "key",
# "token", "code" or "password", and cuts secrets from paths, for errors and Insights
# alike; http_cookie drops the session cookie from the request headers, and
# http_authorization an MCP token. filter_args keeps function arguments, which can be
# members, out of backtraces, and filter_disable_assigns keeps LiveView assigns out of
# Insights for the same reason. Query events are off: the
# nightly refresh writes row by row, and they filled the plan's daily Insights cap.
config :honeybadger,
  app: :sarduty,
  environment_name: config_env(),
  insights_enabled: true,
  insights_config: %{ecto: %{disabled: true}},
  use_logger: true,
  ecto_repos: [App.Repo],
  filter: Web.HoneybadgerFilter,
  notice_filter: Web.HoneybadgerFilter,
  event_filter: Web.HoneybadgerFilter,
  filter_args: true,
  filter_disable_assigns: true,
  filter_keys: [
    :password,
    :current_password,
    :password_confirmation,
    :access_key,
    :new_d4h_access_key,
    :token,
    :code,
    :http_cookie,
    :http_authorization,
    :__changed__,
    :flash,
    :_csrf_token
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
