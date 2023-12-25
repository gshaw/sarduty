defmodule App.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # credo:disable-for-next-line Credo.Check.Readability.ImplTrue
  @impl true
  def start(_type, _args) do
    App.Release.migrate()

    children = [
      Web.Telemetry,
      App.Repo,
      App.Vault,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:sarduty, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:sarduty, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: App.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: App.Finch},
      # Start a worker by calling: App.Worker.start_link(arg)
      # {App.Worker, arg},
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

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") != nil
  end
end
