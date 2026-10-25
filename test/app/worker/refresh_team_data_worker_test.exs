defmodule App.Worker.RefreshTeamDataWorkerTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Worker.RefreshTeamDataWorker

  test "a team has one refresh waiting or running at a time" do
    team = team_fixture()
    other = team_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, first} = RefreshTeamDataWorker.enqueue(team)
      {:ok, second} = RefreshTeamDataWorker.enqueue(team)
      {:ok, third} = RefreshTeamDataWorker.enqueue(other)

      refute first.conflict?
      assert second.conflict?
      refute third.conflict?
    end)
  end
end
