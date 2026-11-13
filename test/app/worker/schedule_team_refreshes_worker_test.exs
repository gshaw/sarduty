defmodule App.Worker.ScheduleTeamRefreshesWorkerTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.DataFixtures

  alias App.Model.Team
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.ScheduleTeamRefreshesWorker

  @none %{retrying: [], cancelled: []}

  defp team(id, refreshed_at), do: %Team{id: id, d4h_refreshed_at: refreshed_at}

  describe "due_since/1" do
    test "is today's 06:00 UTC from then on, and yesterday's before it" do
      assert ScheduleTeamRefreshesWorker.due_since(~U[2026-11-13 06:00:00Z]) ==
               ~U[2026-11-13 06:00:00Z]

      assert ScheduleTeamRefreshesWorker.due_since(~U[2026-11-13 23:50:00Z]) ==
               ~U[2026-11-13 06:00:00Z]

      assert ScheduleTeamRefreshesWorker.due_since(~U[2026-11-13 05:59:59Z]) ==
               ~U[2026-11-12 06:00:00Z]
    end
  end

  describe "plan/3" do
    test "a team not refreshed since 06:00 is due, and one never refreshed" do
      teams = [
        team(1, ~U[2026-11-13 06:04:00Z]),
        team(2, ~U[2026-11-13 05:59:00Z]),
        team(3, nil)
      ]

      plan = ScheduleTeamRefreshesWorker.plan(teams, @none, ~U[2026-11-13 06:10:00Z])

      assert plan.teams == 3
      assert Enum.map(plan.due, & &1.id) == [2, 3]
      assert Enum.map(plan.queue, & &1.id) == [2, 3]
      assert plan.overdue == []
    end

    test "a team still due 2 hours after 06:00 is overdue, until it refreshes" do
      teams = [team(1, ~U[2026-11-12 06:04:00Z]), team(2, ~U[2026-11-13 08:30:00Z])]

      assert %{overdue: []} =
               ScheduleTeamRefreshesWorker.plan(teams, @none, ~U[2026-11-13 07:59:00Z])

      assert %{overdue: [%Team{id: 1}]} =
               ScheduleTeamRefreshesWorker.plan(teams, @none, ~U[2026-11-13 08:00:00Z])
    end

    test "a crashed refresh from last night is queued again the next morning" do
      # The case behind this design: 11-12's run never pinged, and waited a day.
      teams = [team(1, ~U[2026-11-12 06:04:00Z])]

      assert %{queue: [%Team{id: 1}]} =
               ScheduleTeamRefreshesWorker.plan(teams, @none, ~U[2026-11-13 06:00:00Z])
    end

    test "a team waiting to retry isn't queued again, but still counts as overdue" do
      teams = [team(1, nil)]
      held = %{retrying: [1], cancelled: []}

      plan = ScheduleTeamRefreshesWorker.plan(teams, held, ~U[2026-11-13 09:00:00Z])

      assert plan.queue == []
      assert [%Team{id: 1}] = plan.overdue
    end

    test "a team cancelled for its key waits for the next 06:00 and never pages" do
      teams = [team(1, nil)]
      held = %{retrying: [], cancelled: [1]}

      plan = ScheduleTeamRefreshesWorker.plan(teams, held, ~U[2026-11-13 09:00:00Z])

      assert plan.due == []
      assert plan.queue == []
      assert plan.overdue == []
    end
  end

  describe "perform/1" do
    setup do
      Application.put_env(:sarduty, :healthchecks_url, "https://hc.test/refresh")
      on_exit(fn -> Application.delete_env(:sarduty, :healthchecks_url) end)

      test = self()

      Req.Test.stub(App.Adapter.Healthchecks, fn conn ->
        send(test, {:ping, conn.request_path})
        Plug.Conn.send_resp(conn, 200, "OK")
      end)
    end

    test "queues each due team, skips one up to date or retrying, and pings" do
      due = team_fixture()
      fresh = team_fixture(%{d4h_refreshed_at: DateTime.utc_now()})
      retrying = team_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        %{team_id: retrying.id}
        |> RefreshTeamDataWorker.new()
        |> Ecto.Changeset.change(state: "retryable")
        |> Repo.insert!()

        assert perform_job(ScheduleTeamRefreshesWorker, %{}) == :ok

        assert_enqueued(worker: RefreshTeamDataWorker, args: %{team_id: due.id})
        refute_enqueued(worker: RefreshTeamDataWorker, args: %{team_id: fresh.id})

        refute_enqueued(
          worker: RefreshTeamDataWorker,
          args: %{team_id: retrying.id},
          state: "available"
        )
      end)

      assert_received {:ping, path} when path in ["/refresh", "/refresh/fail"]
    end
  end
end
