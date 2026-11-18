defmodule App.Worker.DeleteDraftFilesWorker do
  @moduledoc """
  Deletes a discarded AI writing draft's PDFs from the file store, then its row
  (App.Operation.SaveDraft, #1089), so Start over, Discard them, and a save never wait
  on the store. A draft gone already, as with its team, has nothing left to do.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias App.Model.AIDraft
  alias App.Operation.SaveDraft

  @doc "Queues the delete, in the transaction that marks the draft discarded."
  def enqueue(%AIDraft{id: id}), do: %{draft_id: id} |> new() |> Oban.insert!()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"draft_id" => id}}) do
    case AIDraft.get_discarded(id) do
      nil -> :ok
      draft -> SaveDraft.delete_files(draft)
    end
  end
end
