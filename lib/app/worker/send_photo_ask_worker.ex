defmodule App.Worker.SendPhotoAskWorker do
  @moduledoc """
  Emails one ask for a photo (App.Operation.AskForPhoto.deliver/3), or one ask for an
  activity's photos (#1034, App.Operation.AskForActivityPhotos.deliver/3). A refusal is
  tried again over about an hour; the last one marks the ask's email failed, which the
  member's ID Card tab shows for an ask for a photo.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 5

  alias App.Model.ActivityPhotoAsk
  alias App.Model.PhotoAsk
  alias App.Operation.AskForActivityPhotos
  alias App.Operation.AskForPhoto

  @doc "Queues the ask's email. Call it in the transaction that saves the ask."
  def enqueue(%PhotoAsk{id: id}), do: %{photo_ask_id: id} |> new() |> Oban.insert!()

  def enqueue(%ActivityPhotoAsk{id: id}),
    do: %{activity_photo_ask_id: id} |> new() |> Oban.insert!()

  # After 1, 5, 15, then 30 minutes.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: Enum.at([60, 300, 900, 1800], attempt - 1)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_ask_id" => id}} = job) do
    AskForPhoto.deliver(id, job.attempt >= job.max_attempts, DateTime.utc_now())
  end

  def perform(%Oban.Job{args: %{"activity_photo_ask_id" => id}} = job) do
    AskForActivityPhotos.deliver(id, job.attempt >= job.max_attempts, DateTime.utc_now())
  end
end
