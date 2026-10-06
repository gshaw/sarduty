defmodule App.Worker.ScheduleTeamSyncsWorker do
  @moduledoc "Queues a D4H sync for every team with a key, every 10 minutes (#163)."

  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.Team
  alias App.Worker.SyncTeamChangesWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Team.get_all()
    |> Enum.filter(&(&1.d4h_team_id && &1.d4h_access_key not in [nil, ""]))
    |> Enum.each(&SyncTeamChangesWorker.enqueue/1)

    :ok
  end
end
