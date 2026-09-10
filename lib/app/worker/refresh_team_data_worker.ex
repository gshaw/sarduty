defmodule App.Worker.RefreshTeamDataWorker do
  use Oban.Worker, queue: :refresh, max_attempts: 3

  alias App.Model.Team
  alias App.Operation.RefreshD4HData

  # Retry a failed refresh after 15, then 30 minutes, rather than waiting a day.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 15 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team = Team.get!(team_id)
    {:ok, team} = Team.update(team, %{d4h_refresh_result: "Refreshing"})
    broadcast_team_refresh(team)

    try do
      case RefreshD4HData.call(team) do
        {:ok, team} ->
          {:ok, team} = Team.update(team, %{d4h_refresh_result: "OK"})
          broadcast_team_refresh(team)
          ping_healthchecks()
          :ok

        # Only a person can fix a missing or rejected key, so a cancelled job is
        # neither retried nor sent to Honeybadger.
        {:error, reason} ->
          message = RefreshD4HData.error_message(reason)
          {:ok, team} = Team.update(team, %{d4h_refresh_result: "Error: #{message}"})
          broadcast_team_refresh(team)
          {:cancel, message}
      end
    rescue
      e ->
        {:ok, team} = Team.update(team, %{d4h_refresh_result: "Error: #{Exception.message(e)}"})
        broadcast_team_refresh(team)
        # Reraise so the job fails with the real exception and stacktrace, which
        # App.Worker.ErrorReporter sends to Honeybadger.
        reraise e, __STACKTRACE__
    end
  end

  defp broadcast_team_refresh(team) do
    Phoenix.PubSub.broadcast(App.PubSub, "team_refresh", {:team_refreshed, team})
  end

  defp ping_healthchecks do
    case Application.get_env(:sarduty, :healthchecks_url) do
      nil -> :ok
      "" -> :ok
      url -> Req.get(url)
    end
  end
end
