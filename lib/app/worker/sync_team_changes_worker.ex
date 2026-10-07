defmodule App.Worker.SyncTeamChangesWorker do
  @moduledoc """
  Copies one team's D4H changes (App.Operation.SyncD4HChanges), every 10 minutes and when
  a manager opens the team's dashboard after more than 2 minutes (#163). One job per team
  at a time, on its own queue so it never waits behind another team's full refresh.

  A sync that changed something, failed, or found the key rejected is recorded as a
  `d4h_team_sync` event; a quiet one isn't.

  A failed sync isn't retried: the next one is 10 minutes away. Honeybadger hears about
  it only after an hour of failures. A missing or rejected key is left for the nightly
  refresh to report on the dashboards, and a rejected one stops the syncs until a new
  key is saved or a nightly refresh works again.
  """

  use Oban.Worker,
    queue: :sync,
    max_attempts: 1,
    unique: [keys: [:team_id], states: [:available, :scheduled, :executing]]

  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.SyncD4HChanges
  alias App.Worker.PushPassUpdatesWorker

  require Logger

  @doc "Queues a sync for the team, unless one is already queued or running."
  def enqueue(%Team{} = team), do: %{team_id: team.id} |> new() |> Oban.insert()

  @doc "Queues a sync when the team syncs and its last one is over 2 minutes old."
  def enqueue_if_stale(%Team{} = team, now) do
    if stale?(team, now), do: enqueue(team), else: :fresh
  end

  def stale?(%Team{} = team, now) do
    syncs?(team) and (team.d4h_synced_at == nil or DateTime.diff(now, team.d4h_synced_at) > 120)
  end

  @doc "Whether the team has a key D4H hasn't rejected."
  def syncs?(%Team{} = team) do
    team.d4h_team_id != nil and team.d4h_access_key not in [nil, ""] and
      not SyncD4HChanges.key_rejected?(team)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team = Team.get!(team_id)

    if Team.refresh_state(team.d4h_refresh_result) == :refreshing,
      do: {:cancel, "a full refresh is running"},
      else: sync(team)
  end

  defp sync(team) do
    started_at = DateTime.utc_now()

    case SyncD4HChanges.call(team) do
      {:ok, _team, []} ->
        :ok

      {:ok, team, changed} ->
        record(team, started_at, %{outcome: "changed", lists: changed})
        Phoenix.PubSub.broadcast(App.PubSub, "team_refresh", {:team_refreshed, team})
        %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert!()
        :ok

      {:error, {:key_rejected, status} = reason} ->
        record(team, started_at, %{outcome: "key_rejected", status: status})
        SyncD4HChanges.record_key_rejected(team)
        {:cancel, inspect(reason)}

      {:error, reason} ->
        {:cancel, inspect(reason)}
    end
  rescue
    error ->
      record(team, nil, %{outcome: "failed", error: error |> Exception.message() |> short()})
      {_team, report?} = SyncD4HChanges.record_failure(team, DateTime.utc_now())
      Logger.warning("D4H sync failed for team #{team.id}: #{Exception.message(error)}")

      if report?,
        do: Honeybadger.notify(error, metadata: %{team_id: team.id}, stacktrace: __STACKTRACE__)

      {:cancel, Exception.message(error)}
  end

  defp record(team, started_at, data) do
    now = DateTime.utc_now()
    duration_ms = started_at && Event.duration_ms(started_at, now)

    Event.record!(:d4h_team_sync,
      team_id: team.id,
      duration_ms: duration_ms,
      data: data,
      occurred_at: now
    )
  end

  defp short(message), do: String.slice(message, 0, 500)
end
