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

  @doc "Queues a push of the team's changed passes, unless one is already waiting."
  def enqueue(%Team{id: id}), do: enqueue_team_ids([id])

  @doc "Queues a push for each of these teams, by id."
  def enqueue_team_ids(team_ids),
    do: team_ids |> Enum.map(&new(%{team_id: &1})) |> Enum.each(&Oban.insert!/1)

  # Queued after each team refresh, so a failed push never fails the refresh.
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team = Team.get!(team_id)
    now = DateTime.utc_now()
    PushPassUpdates.call(team, now)
    UpdateGooglePasses.call(team, now)
  end
end
