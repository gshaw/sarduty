defmodule App.Worker.SendChoreEventsWorker do
  use Oban.Worker, queue: :refresh, max_attempts: 1

  alias App.Model.Event
  alias App.Model.Team
  alias App.Operation.SendChoreEvents

  # Sends a team's accepted chores to D4H (#341), after its nightly full refresh
  # (App.Worker.RefreshTeamDataWorker). One try: an event that did not go stays marked
  # for tomorrow night.
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    team = Team.get!(team_id)
    started_at = DateTime.utc_now()
    result = SendChoreEvents.call(team, started_at)
    now = DateTime.utc_now()

    if result.sent + result.failed > 0 do
      Event.record!(:chore_events_sent,
        team_id: team.id,
        duration_ms: Event.duration_ms(started_at, now),
        data: result,
        occurred_at: now
      )
    end

    :ok
  end
end
