defmodule App.Worker.RenewLetterCodesWorker do
  @moduledoc """
  Renews every letter's old reference number (App.Operation.RenewLetterCodes), a few at
  a time, a minute apart, since Typst prints on production's shared CPU. Started once
  after #970 deploys:

      bin/sarduty rpc "App.Worker.RenewLetterCodesWorker.enqueue()"

  `RenewLetterCodes.remaining()` is 0 when it's done. Part 3 of #970 deletes it.
  """

  use Oban.Worker, queue: :bulk, max_attempts: 3

  alias App.Operation.RenewLetterCodes

  @batch 10

  def enqueue, do: %{after_id: 0} |> new() |> Oban.insert!()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"after_id" => after_id}}) do
    case RenewLetterCodes.batch(after_id, @batch) do
      nil ->
        :ok

      last_id ->
        %{after_id: last_id} |> new(schedule_in: 60) |> Oban.insert!()
        :ok
    end
  end
end
