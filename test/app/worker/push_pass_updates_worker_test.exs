defmodule App.Worker.PushPassUpdatesWorkerTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.DataFixtures

  alias App.Worker.PushPassUpdatesWorker

  test "a team has one pass push waiting, and a running one doesn't block the next" do
    team = team_fixture()

    Oban.Testing.with_testing_mode(:manual, fn ->
      PushPassUpdatesWorker.enqueue(team)
      PushPassUpdatesWorker.enqueue(team)
      assert [job] = all_enqueued(worker: PushPassUpdatesWorker)

      job |> Ecto.Changeset.change(state: "executing") |> Repo.update!()
      PushPassUpdatesWorker.enqueue(team)
      assert [_waiting] = all_enqueued(worker: PushPassUpdatesWorker)
    end)
  end
end
