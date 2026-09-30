defmodule App.Worker.PushPassUpdatesWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias App.Model.Team
  alias App.Operation.PushPassUpdates

  # Queued after each team refresh, so a failed push never fails the refresh.
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team_id |> Team.get!() |> PushPassUpdates.call(DateTime.utc_now())
  end
end
