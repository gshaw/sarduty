defmodule App.Worker.PruneEventsWorker do
  @moduledoc """
  Deletes events past their kind's retention, D4H changes past theirs, MCP calls past
  theirs, and snoozes a day after they end, once a night (App.Model.Event,
  App.Model.D4HChange, App.Model.MCPCall, App.Model.AttentionSnooze).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Model.AttentionSnooze
  alias App.Model.D4HChange
  alias App.Model.Event
  alias App.Model.MCPCall

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    count = Event.prune(now)
    if count > 0, do: Logger.info("Pruned #{count} events")
    count = D4HChange.prune(now)
    if count > 0, do: Logger.info("Pruned #{count} D4H changes")
    calls = MCPCall.prune(now)
    if calls > 0, do: Logger.info("Pruned #{calls} MCP calls")
    snoozes = AttentionSnooze.prune(now)
    if snoozes > 0, do: Logger.info("Pruned #{snoozes} attention snoozes")
    :ok
  end
end
