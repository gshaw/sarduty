defmodule App.Worker.WriteHistoryLineWorker do
  @moduledoc """
  Writes a saved report's History line with AI, a few seconds after the save
  (App.Operation.WriteHistoryLine). Two tries: the line is only worth having soon, and a
  version that already has one is left alone, so a second run spends nothing.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  alias App.Model.ReportVersion
  alias App.Operation.WriteHistoryLine

  @doc "Queues the line for a version just saved."
  def enqueue(%ReportVersion{id: id}), do: %{version_id: id} |> new() |> Oban.insert!()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version_id" => id}}), do: WriteHistoryLine.call(id)
end
