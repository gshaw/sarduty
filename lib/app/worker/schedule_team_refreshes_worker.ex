defmodule App.Worker.ScheduleTeamRefreshesWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.Team
  alias App.Worker.RefreshTeamDataWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Team.get_all()
    |> Enum.filter(& &1.d4h_team_id)
    |> Enum.each(fn team ->
      %{team_id: team.id}
      |> RefreshTeamDataWorker.new()
      |> Oban.insert()
    end)

    :ok
  end
end
