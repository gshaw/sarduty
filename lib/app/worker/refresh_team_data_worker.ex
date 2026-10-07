defmodule App.Worker.RefreshTeamDataWorker do
  use Oban.Worker, queue: :refresh, max_attempts: 3

  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.RefreshD4HData
  alias App.Worker.PushPassUpdatesWorker

  # Retry a failed refresh after 15, then 30 minutes, rather than waiting a day.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 15 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team = Team.get!(team_id)
    started_at = DateTime.utc_now()
    {:ok, team} = Team.update(team, %{d4h_refresh_result: "Refreshing"})
    broadcast_team_refresh(team)

    try do
      team |> RefreshD4HData.call() |> finish(team, started_at)
    rescue
      e ->
        record(team, started_at, %{outcome: "failed", error: e |> Exception.message() |> short()})

        {:ok, team} = Team.update(team, %{d4h_refresh_result: "Error: #{Exception.message(e)}"})
        broadcast_team_refresh(team)
        # Reraise so the job fails with the real exception and stacktrace, which
        # App.Worker.ErrorReporter sends to Honeybadger.
        reraise e, __STACKTRACE__
    end
  end

  defp finish({:ok, team, missed}, _team, started_at) do
    record(team, started_at, %{outcome: "ok", missed: missed})
    {:ok, team} = Team.update(team, %{d4h_refresh_result: "OK"})
    broadcast_team_refresh(team)
    %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert!()
    :ok
  end

  # Only a person can fix a missing or rejected key, so a cancelled job is neither
  # retried nor sent to Honeybadger.
  defp finish({:error, reason}, team, started_at) do
    message = RefreshD4HData.error_message(reason)
    record(team, started_at, %{outcome: "key_error", error: message})
    {:ok, team} = Team.update(team, %{d4h_refresh_result: "Error: #{message}"})
    broadcast_team_refresh(team)
    {:cancel, message}
  end

  defp broadcast_team_refresh(team) do
    Phoenix.PubSub.broadcast(App.PubSub, "team_refresh", {:team_refreshed, team})
  end

  # One event per attempt, so a retried team shows each failure.
  defp record(team, started_at, data) do
    now = DateTime.utc_now()

    Event.record!(:d4h_team_refresh,
      team_id: team.id,
      duration_ms: Event.duration_ms(started_at, now),
      data: data,
      occurred_at: now
    )
  end

  defp short(message), do: String.slice(message, 0, 500)
end
