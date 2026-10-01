defmodule App.Worker.PushPassUpdatesWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.Team
  alias App.Operation.PushPassUpdates
  alias App.Operation.UpdateGooglePasses

  # Queued after each team refresh, so a failed push never fails the refresh.
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team = Team.get!(team_id)
    now = DateTime.utc_now()
    PushPassUpdates.call(team, now)
    UpdateGooglePasses.call(team, now)
  end
end
