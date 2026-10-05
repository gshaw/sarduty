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

config :sarduty, App.Adapter.Mapbox, access_token: System.fetch_env!("MAPBOX_ACCESS_TOKEN")
config :sarduty, :healthchecks_url, System.get_env("HEALTHCHECKS_URL")

# Apple Wallet passes for member ID cards. Optional: without them the ID Card tab
# offers no pass. The certificate and key are PEM text.
config :sarduty, :apple_pass,
  pass_type_id: System.get_env("APPLE_PASS_TYPE_ID"),
  team_id: System.get_env("APPLE_TEAM_ID"),
  certificate: System.get_env("APPLE_PASS_CERTIFICATE"),
  private_key: System.get_env("APPLE_PASS_PRIVATE_KEY")

# Google Wallet passes for member ID cards. Optional, like Apple's. The service account
# is the key file's JSON. Google refuses a pass whose images it can't load, and it can't
# reach a dev server, so only production passes have a logo and photo.
config :sarduty, :google_wallet,
  issuer_id: System.get_env("GOOGLE_WALLET_ISSUER_ID"),
  service_account: System.get_env("GOOGLE_WALLET_SERVICE_ACCOUNT"),
  images: config_env() == :prod

# Twilio, for texting login codes. Optional: without all four, there is no text login.
# Dev only logs texts unless DEV_SEND_SMS is set, like DEV_SEND_EMAIL for mail. Tests
# ignore the env vars and turn text login on themselves.
if config_env() != :test do
  config :sarduty, App.Adapter.Twilio,
    account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
    api_key_sid: System.get_env("TWILIO_API_KEY_SID"),
    api_key_secret: System.get_env("TWILIO_API_KEY_SECRET"),
    from_number: System.get_env("TWILIO_FROM_NUMBER"),
    deliver: config_env() == :prod or System.get_env("DEV_SEND_SMS") == "true"
end

if config_env() == :prod do
  config :sarduty, Web.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT", "8080"))
    ],
    url: [
      host: System.fetch_env!("PHX_HOST"),
      port: 443,
      scheme: "https"
    ],
    # The verify site's LiveView connects from its own host (Web.VerifyHost). Not :conn:
    # behind Fly's proxy the app sees http on 8080, which no browser origin matches.
    check_origin: [
      "//#{System.fetch_env!("PHX_HOST")}",
      "//verify.#{System.fetch_env!("PHX_HOST")}"
    ]

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
    adapter: App.Adapter.CloudflareEmail,
    account_id: System.fetch_env!("CLOUDFLARE_ACCOUNT_ID"),
    api_token: System.fetch_env!("CLOUDFLARE_EMAIL_TOKEN")
end
