defmodule App.Worker.DemoTeamsWorker do
  @moduledoc """
  Every hour, for Try a demo (#857): deletes each demo past its time
  (App.Operation.DeleteDemo), built or never opened. A delete that fails is tried again
  the next hour. The banner says when a demo goes, so nobody is emailed first.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Model.DemoTeam
  alias App.Operation.DeleteDemo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(DateTime.utc_now(:second))

  @doc false
  def run(now) do
    for demo <- DemoTeam.expired(now) do
      with {:error, reason} <- DeleteDemo.call(demo),
           do: Logger.error("Try a demo #{demo.id} was not deleted: #{inspect(reason)}")
    end

    :ok
  end
end
