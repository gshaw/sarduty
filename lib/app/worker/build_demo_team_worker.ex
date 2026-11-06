defmodule App.Worker.BuildDemoTeamWorker do
  @moduledoc """
  Builds a visitor's demo the first time they open its link (App.Operation.BuildDemoTeam),
  while the page waits. One per demo at a time, and never retried: the page offers Try
  again. Its own queue, so a visitor never waits behind the nightly refresh.
  """
  use Oban.Worker,
    queue: :demos,
    max_attempts: 1,
    unique: [keys: [:demo_id], states: [:available, :scheduled, :executing], period: :infinity]

  alias App.Model.DemoTeam
  alias App.Operation.BuildDemoTeam
  alias App.Repo

  def enqueue(%DemoTeam{id: id}), do: %{demo_id: id} |> new() |> Oban.insert()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"demo_id" => id}}) do
    case Repo.get(DemoTeam, id) do
      nil ->
        {:cancel, "no demo"}

      demo ->
        case BuildDemoTeam.call(demo, DateTime.utc_now(:second)) do
          {:ok, _team} -> :ok
          {:error, reason} -> {:cancel, inspect(reason)}
        end
    end
  end
end
