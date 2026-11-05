defmodule App.Worker.PruneEventsWorker do
  @moduledoc """
  Deletes events past their kind's retention, D4H changes past theirs, MCP calls past
  theirs, and snoozes a day after they end, once a night (App.Model.Event,
  App.Model.D4HChange, App.Model.MCPCall, App.Model.AttentionSnooze). Also agent
  registrations and Allows that never connected (#761), and reports deleted 30 days ago
  with their versions (#834), and database copies a team delete took 7 days ago.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Model.AgentClient
  alias App.Model.AgentConnection
  alias App.Model.AttentionSnooze
  alias App.Model.D4HChange
  alias App.Model.Event
  alias App.Model.MCPCall
  alias App.Model.SavedReport
  alias App.Operation.DeleteTeam

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
    pending = AgentConnection.prune_pending(now)
    if pending > 0, do: Logger.info("Pruned #{pending} agent Allows never connected")
    clients = AgentClient.prune(now)
    if clients > 0, do: Logger.info("Pruned #{clients} agent registrations")
    reports = SavedReport.prune_deleted(now)
    if reports > 0, do: Logger.info("Pruned #{reports} deleted reports")
    snapshots = DeleteTeam.prune_snapshots(now)
    if snapshots > 0, do: Logger.info("Pruned #{snapshots} team delete snapshots")
    :ok
  end
end
