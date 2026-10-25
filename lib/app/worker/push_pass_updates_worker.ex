defmodule App.Worker.PushPassUpdatesWorker do
  # One per team waiting. A running one doesn't block the next, since it may have read
  # the cards before the change that queued it.
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [keys: [:team_id], states: [:available, :scheduled], period: :infinity]

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
