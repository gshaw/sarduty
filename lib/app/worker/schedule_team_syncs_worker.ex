defmodule App.Worker.ScheduleTeamSyncsWorker do
  @moduledoc """
  Queues a D4H sync for every team with a working key, every 10 minutes (#163), and
  the job that tells Healthchecks when they're done.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.DemoTeam
  alias App.Model.Team
  alias App.Worker.FinishRunWorker
  alias App.Worker.SyncTeamChangesWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    real = Enum.filter(Team.get_all_real(), &SyncTeamChangesWorker.syncs?/1)
    Enum.each(real ++ demos_in_use(now), &SyncTeamChangesWorker.enqueue/1)
    FinishRunWorker.start("sync", length(real), now)
    :ok
  end

  # A Try a demo copy syncs only while someone has it open (#857), and stays out of the
  # run's count of teams.
  defp demos_in_use(now) do
    case DemoTeam.team_ids_in_use(now) do
      [] -> []
      ids -> Enum.filter(Team.get_all(), &(&1.id in ids and SyncTeamChangesWorker.syncs?(&1)))
    end
  end
end
