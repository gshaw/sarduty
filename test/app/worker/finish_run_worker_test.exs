defmodule App.Worker.FinishRunWorkerTest do
  use App.DataCase

  alias App.Model.Event
  alias App.Worker.FinishRunWorker
  alias App.Worker.RefreshTeamDataWorker
  alias App.Worker.ScheduleTeamRefreshesWorker

  @started_at ~U[2026-10-07 06:00:00.000000Z]

  setup do
    Application.put_env(:sarduty, :healthchecks_url, "https://hc.test/refresh")
    on_exit(fn -> Application.delete_env(:sarduty, :healthchecks_url) end)

    test = self()

    Req.Test.stub(App.Adapter.Healthchecks, fn conn ->
      send(test, {:ping, conn.request_path})
      Plug.Conn.send_resp(conn, 200, "OK")
    end)
  end

  defp perform(run) do
    args = %{"run" => run, "teams" => 3, "started_at" => DateTime.to_iso8601(@started_at)}
    FinishRunWorker.perform(%Oban.Job{args: args})
  end

  # Inline Oban testing stores no jobs, so these are written straight to the table.
  defp refresh_job(state, attrs \\ %{}) do
    %{team_id: 1}
    |> RefreshTeamDataWorker.new()
    |> Ecto.Changeset.change(
      Map.merge(%{state: state, inserted_at: DateTime.add(@started_at, 1, :second)}, attrs)
    )
    |> Repo.insert!()
  end

  test "waits while jobs are left, fails on any out of attempts, else succeeds" do
    assert FinishRunWorker.outcome(3, 0) == :wait
    assert FinishRunWorker.outcome(1, 2) == :wait
    assert FinishRunWorker.outcome(0, 0) == :success
    assert FinishRunWorker.outcome(0, 1) == :fail
  end

  test "waits for a refresh that will retry" do
    refresh_job("retryable")

    assert perform("refresh") == {:snooze, 60}
    refute_received {:ping, _}
  end

  test "a job left executing from before the run doesn't hold it open" do
    refresh_job("executing", %{inserted_at: DateTime.add(@started_at, -120, :day)})

    assert perform("refresh") == :ok
    assert_received {:ping, "/refresh"}
  end

  test "fails the run for a refresh that ran out of attempts during it" do
    refresh_job("discarded", %{discarded_at: DateTime.add(@started_at, 30, :minute)})

    assert perform("refresh") == :ok
    assert_received {:ping, "/refresh/fail"}
  end

  test "a cancelled refresh, or one discarded before the run, doesn't fail it" do
    refresh_job("cancelled", %{cancelled_at: DateTime.add(@started_at, 5, :minute)})
    refresh_job("discarded", %{discarded_at: DateTime.add(@started_at, -1, :day)})

    assert perform("refresh") == :ok
    assert_received {:ping, "/refresh"}
  end

  test "records the run, with what its team events and rate limits say" do
    during = DateTime.add(@started_at, 1, :minute)
    before = DateTime.add(@started_at, -1, :minute)
    Event.record!(:d4h_team_sync, data: %{outcome: "changed"}, occurred_at: during)
    Event.record!(:d4h_team_sync, data: %{outcome: "failed"}, occurred_at: during)
    Event.record!(:d4h_team_sync, data: %{outcome: "failed"}, occurred_at: before)
    Event.record!(:d4h_rate_limited, occurred_at: during)

    assert perform("sync") == :ok

    assert %Event{data: data, duration_ms: duration_ms} = Event.get_last(:d4h_sync_round)
    assert is_integer(duration_ms)

    assert data == %{
             "outcome" => "success",
             "teams" => 3,
             "changed" => 1,
             "failed" => 1,
             "key_rejected" => 0,
             "rate_limited" => 1
           }
  end

  test "the scheduler pings the start, and the run's end once its jobs are done" do
    ScheduleTeamRefreshesWorker.perform(%Oban.Job{})

    assert_received {:ping, "/refresh/start"}
    assert_received {:ping, "/refresh"}
  end
end
