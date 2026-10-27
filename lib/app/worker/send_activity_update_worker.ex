defmodule App.Worker.SendActivityUpdateWorker do
  @moduledoc """
  Emails one update (App.Operation.SendActivityUpdate.deliver/3). A refusal is tried
  again over about an hour, until the activity starts; the last refusal marks the update
  failed, which Send an update shows.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 5

  alias App.Model.ActivityUpdate
  alias App.Operation.SendActivityUpdate

  @doc "Queues the update's email. Call it in the transaction that inserts the update."
  def enqueue(%ActivityUpdate{id: id}), do: %{activity_update_id: id} |> new() |> Oban.insert!()

  # After 1, 5, 15, then 30 minutes.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: Enum.at([60, 300, 900, 1800], attempt - 1)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity_update_id" => id}} = job) do
    SendActivityUpdate.deliver(id, job.attempt >= job.max_attempts, DateTime.utc_now())
  end
end
