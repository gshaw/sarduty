defmodule App.Worker.PushPassUpdatesWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Worker.PushPassUpdatesWorker

  test "a team has one pass push waiting, and a running one doesn't block the next" do
    team = team_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, first} = %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert()
      {:ok, second} = %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert()
      assert second.conflict?

      first |> Ecto.Changeset.change(state: "executing") |> Repo.update!()
      {:ok, third} = %{team_id: team.id} |> PushPassUpdatesWorker.new() |> Oban.insert()
      refute third.conflict?
    end)
  end
end
