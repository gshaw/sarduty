defmodule App.Worker.RefreshTeamDataWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Worker.RefreshTeamDataWorker

  test "a team has one refresh waiting or running at a time" do
    team = team_fixture()
    other = team_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, first} = %{team_id: team.id} |> RefreshTeamDataWorker.new() |> Oban.insert()
      {:ok, second} = %{team_id: team.id} |> RefreshTeamDataWorker.new() |> Oban.insert()
      {:ok, third} = %{team_id: other.id} |> RefreshTeamDataWorker.new() |> Oban.insert()

      refute first.conflict?
      assert second.conflict?
      refute third.conflict?
    end)
  end
end
