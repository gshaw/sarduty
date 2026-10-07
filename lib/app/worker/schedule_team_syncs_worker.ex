defmodule App.Worker.ScheduleTeamSyncsWorker do
  @moduledoc """
  Queues a D4H sync for every team with a working key, every 10 minutes (#163), and
  the job that tells Healthchecks when they're done.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.Team
  alias App.Worker.FinishRunWorker
  alias App.Worker.SyncTeamChangesWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    teams = Enum.filter(Team.get_all(), &SyncTeamChangesWorker.syncs?/1)
    Enum.each(teams, &SyncTeamChangesWorker.enqueue/1)
    FinishRunWorker.start("sync", length(teams), now)
    :ok
  end
end
