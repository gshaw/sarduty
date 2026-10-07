defmodule App.Worker.PruneEventsWorker do
  @moduledoc """
  Deletes events past their kind's retention, and D4H changes past theirs, once a night
  (App.Model.Event, App.Model.D4HChange).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Model.D4HChange
  alias App.Model.Event

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    count = Event.prune(now)
    if count > 0, do: Logger.info("Pruned #{count} events")
    count = D4HChange.prune(now)
    if count > 0, do: Logger.info("Pruned #{count} D4H changes")
    :ok
  end
end
