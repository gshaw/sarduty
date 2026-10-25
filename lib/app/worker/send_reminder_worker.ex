defmodule App.Worker.SendReminderWorker do
  @moduledoc """
  Emails one reminder (App.Operation.SendReminders.deliver/3). A refusal is tried again
  over about an hour, until the activity starts; the last refusal marks the reminder
  failed, which its activity's page shows.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 5

  alias App.Model.Reminder
  alias App.Operation.SendReminders

  @doc "Queues the reminder's email. Call it in the transaction that inserts the reminder."
  def enqueue(%Reminder{id: id}), do: %{reminder_id: id} |> new() |> Oban.insert!()

  # After 1, 5, 15, then 30 minutes.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: Enum.at([60, 300, 900, 1800], attempt - 1)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"reminder_id" => id}} = job) do
    SendReminders.deliver(id, job.attempt >= job.max_attempts, DateTime.utc_now())
  end
end
