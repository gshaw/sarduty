import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/sarduty start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :sarduty, Web.Endpoint, server: true
end

if config_env() == :prod do
  config :sarduty, Web.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    http: [
      port: String.to_integer(System.fetch_env!("PORT"))
    ],
    url: [
      host: System.fetch_env!("PHX_HOST"),
      port: 443,
      scheme: "https"
    ],
    force_ssl: [hsts: true]

  config :sarduty, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :sarduty, App.Repo,
    database: System.fetch_env!("DATABASE_PATH"),
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "5")

  config :sarduty, App.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", iv_length: 12, key: Base.decode64!(System.fetch_env!("CLOAK_KEY"))
      }
    ]

  config :sarduty, App.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: System.fetch_env!("MAILGUN_API_KEY"),
    domain: System.fetch_env!("MAILGUN_DOMAIN")
end
