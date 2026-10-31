defmodule App.Worker.PruneEventsWorker do
  @moduledoc """
  Deletes events past their kind's retention, D4H changes past theirs, and MCP calls
  past theirs, once a night (App.Model.Event, App.Model.D4HChange, App.Model.MCPCall).
  Also agent registrations and Allows that never connected (#761).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Model.AgentClient
  alias App.Model.AgentConnection
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
    pending = AgentConnection.prune_pending(now)
    if pending > 0, do: Logger.info("Pruned #{pending} agent Allows never connected")
    clients = AgentClient.prune(now)
    if clients > 0, do: Logger.info("Pruned #{clients} agent registrations")
    :ok
  end
end
