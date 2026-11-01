defmodule App.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias App.Worker.ErrorReporter

  # credo:disable-for-next-line Credo.Check.Readability.ImplTrue
  @impl true
  def start(_type, _args) do
    # Before the supervisor, on a Repo of its own with 2 connections. Phoenix's SQLite
    # template migrates from an Ecto.Migrator child on the app's pool instead, but with 5
    # connections a migration can be prepared against another one's stale schema: a
    # fresh database failed at an ALTER TABLE every time (2026-10-23).
    App.Release.migrate()

    :ok = Oban.Telemetry.attach_default_logger()
    :ok = ErrorReporter.attach()
    :ok = Web.RequestLog.attach()

    children = [
      # Before the Repo, so it sees every transaction.
      App.Repo.SlowLog,
      App.Repo,
      # Before Oban: jobs broadcast refresh progress, and children stop in reverse
      # order, so a job still draining at shutdown needs PubSub running.
      {Phoenix.PubSub, name: App.PubSub},
      App.Vault,
      {App.RateLimit, clean_period: :timer.minutes(1)},
      {Oban, Application.fetch_env!(:sarduty, Oban)},
      {DNSCluster, query: Application.get_env(:sarduty, :dns_cluster_query) || :ignore},
      # Start to serve requests, typically the last entry
      Web.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: App.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  # credo:disable-for-next-line Credo.Check.Readability.ImplTrue
  @impl true
  def config_change(changed, _new, removed) do
    Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
