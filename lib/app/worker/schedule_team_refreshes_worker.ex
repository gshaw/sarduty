defmodule App.Worker.ScheduleTeamRefreshesWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.Team
  alias App.Worker.FinishRunWorker
  alias App.Worker.RefreshTeamDataWorker

  @doc "Queues a refresh of every team now, as the nightly run does."
  def enqueue, do: %{} |> new() |> Oban.insert()

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    teams = Enum.filter(Team.get_all(), & &1.d4h_team_id)
    Enum.each(teams, &RefreshTeamDataWorker.enqueue/1)
    FinishRunWorker.start("refresh", length(teams), now)
    :ok
  end
end
