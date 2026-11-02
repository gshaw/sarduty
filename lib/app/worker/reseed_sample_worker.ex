defmodule App.Worker.ReseedSampleWorker do
  @moduledoc """
  Seeds Coast Range SAR again once a night, after midnight in Vancouver, so its dates
  keep counting back from today (App.SampleRepo.reseed!/1): "last 30 days" always has
  rows, and the coming week always has sign-ups.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case App.SampleRepo.reseed!() do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
