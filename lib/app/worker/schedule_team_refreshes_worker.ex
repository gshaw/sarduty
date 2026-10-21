defmodule App.Worker.ScheduleTeamRefreshesWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.Team
  alias App.Worker.FinishRunWorker
  alias App.Worker.RefreshTeamDataWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    teams = Enum.filter(Team.get_all(), & &1.d4h_team_id)
    Enum.each(teams, &(%{team_id: &1.id} |> RefreshTeamDataWorker.new() |> Oban.insert()))
    FinishRunWorker.start("refresh", length(teams), now)
    :ok
  end
end
