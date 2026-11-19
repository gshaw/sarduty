defmodule App.Worker.PruneEventsWorker do
  @moduledoc """
  Deletes events past their kind's retention, D4H changes past theirs, the words of AI
  asks after 90 days, and snoozes a day after they end, once a night (App.Model.Event,
  App.Model.D4HChange, App.Model.AIAsk, App.Model.AttentionSnooze). Also reports deleted
  30 days ago with their versions (#834), and database copies a team delete took 7 days
  ago.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Model.AIAsk
  alias App.Model.AttentionSnooze
  alias App.Model.D4HChange
  alias App.Model.Event
  alias App.Model.SavedReport
  alias App.Operation.DeleteTeam

  require Logger

  # Each prune and the rows it counts, by table, for the log.
  @prunes [
    {&Event.prune/1, "events"},
    {&D4HChange.prune/1, "d4h_changes"},
    {&AIAsk.prune_words/1, "ai_asks (words cleared)"},
    {&AttentionSnooze.prune/1, "attention_snoozes"},
    {&SavedReport.prune_deleted/1, "reports deleted 30 days ago"},
    {&DeleteTeam.prune_snapshots/1, "team delete snapshots"}
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    for {prune, what} <- @prunes do
      count = prune.(now)
      if count > 0, do: Logger.info("Pruned #{count} #{what}")
    end

    :ok
  end
end
