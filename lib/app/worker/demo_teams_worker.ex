defmodule App.Worker.DemoTeamsWorker do
  @moduledoc """
  Every hour, for Try a demo (#857): emails each demo that goes within a day, and deletes
  each demo past its seventh day (App.Operation.DeleteDemo), built or never opened. A
  delete that fails is tried again the next hour.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Mailer.DemoMailer
  alias App.Model.DemoTeam
  alias App.Operation.DeleteDemo
  alias App.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(DateTime.utc_now(:second))

  @doc false
  def run(now) do
    for demo <- DemoTeam.expired(now) do
      with {:error, reason} <- DeleteDemo.call(demo),
           do: Logger.error("Try a demo #{demo.id} was not deleted: #{inspect(reason)}")
    end

    for demo <- DemoTeam.to_warn(now) do
      with {:ok, _sent} <- DemoMailer.deliver_ending(demo),
           do: demo |> Ecto.Changeset.change(warned_at: now) |> Repo.update!()
    end

    :ok
  end
end
