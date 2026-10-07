defmodule App.Worker.PruneEventsWorker do
  @moduledoc "Deletes events past their kind's retention, once a night (App.Model.Event)."

  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Model.Event

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    count = Event.prune(DateTime.utc_now())
    if count > 0, do: Logger.info("Pruned #{count} events")
    :ok
  end
end
