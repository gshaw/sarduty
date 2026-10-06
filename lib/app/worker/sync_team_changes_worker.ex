defmodule App.Worker.SyncTeamChangesWorker do
  @moduledoc """
  Copies one team's D4H changes (App.Operation.SyncD4HChanges), every 10 minutes and when
  a manager opens the team's dashboard after more than 2 minutes (#163). One job per team
  at a time, on its own queue so it never waits behind another team's full refresh.

  A failed sync isn't retried: the next one is 10 minutes away. Honeybadger hears about
  it only after an hour of failures. A missing or rejected key is left for the nightly
  refresh to report on the dashboards.
  """

  use Oban.Worker,
    queue: :sync,
    max_attempts: 1,
    unique: [keys: [:team_id], states: [:available, :scheduled, :executing]]

  alias App.Model.Team
  alias App.Operation.SyncD4HChanges
  alias App.Worker.PushPassUpdatesWorker

  require Logger

  @doc "Queues a sync for the team, unless one is already queued or running."
  def enqueue(%Team{} = team), do: %{team_id: team.id} |> new() |> Oban.insert()

  @doc "Queues a sync when the team has a key and its last one is over 2 minutes old."
  def enqueue_if_stale(%Team{} = team, now) do
    if stale?(team, now), do: enqueue(team), else: :fresh
  end

  def stale?(%Team{d4h_access_key: key}, _now) when key in [nil, ""], do: false
  def stale?(%Team{d4h_synced_at: nil}, _now), do: true
  def stale?(%Team{d4h_synced_at: synced_at}, now), do: DateTime.diff(now, synced_at) > 120

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team = Team.get!(team_id)

    if Team.refresh_state(team.d4h_refresh_result) == :refreshing,
      do: {:cancel, "a full refresh is running"},
      else: sync(team)
  end

  defp sync(team) do
    case SyncD4HChanges.call(team) do
      {:ok, _team, []} ->
        ping_healthchecks()
        :ok

      {:ok, team, _changed} ->
        Phoenix.PubSub.broadcast(App.PubSub, "team_refresh", {:team_refreshed, team})
        %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert!()
        ping_healthchecks()
        :ok

      {:error, reason} ->
        {:cancel, inspect(reason)}
    end
  rescue
    error ->
      {_team, report?} = SyncD4HChanges.record_failure(team, DateTime.utc_now())
      Logger.warning("D4H sync failed for team #{team.id}: #{Exception.message(error)}")

      if report?,
        do: Honeybadger.notify(error, metadata: %{team_id: team.id}, stacktrace: __STACKTRACE__)

      {:cancel, Exception.message(error)}
  end

  defp ping_healthchecks do
    case Application.get_env(:sarduty, :healthchecks_sync_url) do
      url when url in [nil, ""] -> :ok
      url -> Req.get(url)
    end
  end
end
