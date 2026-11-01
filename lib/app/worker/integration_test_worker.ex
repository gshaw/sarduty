defmodule App.Worker.IntegrationTestWorker do
  @moduledoc """
  An empty job for Adminland's jobs test (#789): one on each queue, each saying on
  `topic/1` that it ran. Nothing to retry: a job that doesn't run is the answer.
  """
  use Oban.Worker, max_attempts: 1

  @doc "The queues the test puts a job on, from config/config.exs."
  def queues, do: Application.fetch_env!(:sarduty, Oban)[:queues] |> Keyword.keys()

  @doc "The PubSub topic a test's jobs report on."
  def topic(ref), do: "integration_test:#{ref}"

  @doc "Puts one job on each queue for the test `ref`."
  def enqueue(ref) do
    queues()
    |> Enum.map(&new(%{ref: ref, queue: &1}, queue: &1))
    |> Oban.insert_all()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ref" => ref, "queue" => queue}}) do
    Phoenix.PubSub.broadcast(App.PubSub, topic(ref), {:integration_job_ran, queue})
  end
end
