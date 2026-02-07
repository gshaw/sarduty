defmodule App.Worker.RefreshTeamDataWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.Team
  alias App.Operation.RefreshD4HData

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team = Team.get!(team_id)
    {:ok, team} = Team.update(team, %{d4h_refresh_result: "Refreshing"})

    try do
      # RefreshD4HData.call(team)
      Team.update(team, %{d4h_refresh_result: "OK"})
      ping_healthchecks()
      :ok
    rescue
      e ->
        message = format_error(e)
        Team.update(team, %{d4h_refresh_result: "Error: #{message}"})
        {:error, message}
    end
  end

  defp ping_healthchecks do
    case Application.get_env(:sarduty, :healthchecks_url) do
      nil -> :ok
      "" -> :ok
      url -> Req.get(url)
    end
  end

  defp format_error(%MatchError{term: {:error, %Req.Response{} = response}}) do
    body =
      case response.body do
        body when is_binary(body) -> body
        body when is_map(body) -> Jason.encode!(body)
        other -> inspect(other)
      end

    "D4H API error (#{response.status}): #{String.slice(body, 0, 500)}"
  end

  defp format_error(e), do: Exception.message(e)
end
