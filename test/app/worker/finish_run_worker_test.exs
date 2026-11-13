defmodule App.Worker.FinishRunWorkerTest do
  use App.DataCase

  alias App.Model.Event
  alias App.Worker.FinishRunWorker
  alias App.Worker.ScheduleTeamSyncsWorker
  alias App.Worker.SyncTeamChangesWorker

  @started_at ~U[2026-10-07 06:00:00.000000Z]

  setup do
    Application.put_env(:sarduty, :healthchecks_sync_url, "https://hc.test/sync")
    on_exit(fn -> Application.delete_env(:sarduty, :healthchecks_sync_url) end)

    test = self()

    Req.Test.stub(App.Adapter.Healthchecks, fn conn ->
      send(test, {:ping, conn.request_path})
      Plug.Conn.send_resp(conn, 200, "OK")
    end)
  end

  defp perform do
    args = %{"run" => "sync", "teams" => 3, "started_at" => DateTime.to_iso8601(@started_at)}
    FinishRunWorker.perform(%Oban.Job{args: args})
  end

  # Inline Oban testing stores no jobs, so these are written straight to the table.
  defp sync_job(state, attrs \\ %{}) do
    %{team_id: 1}
    |> SyncTeamChangesWorker.new()
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

  test "waits for a sync still to run" do
    sync_job("available")

    assert perform() == {:snooze, 5}
    refute_received {:ping, _}
  end

  test "a job left executing from before the round doesn't hold it open" do
    sync_job("executing", %{inserted_at: DateTime.add(@started_at, -120, :day)})

    assert perform() == :ok
    assert_received {:ping, "/sync"}
  end

  test "fails the round for a sync that crashed during it" do
    sync_job("discarded", %{discarded_at: DateTime.add(@started_at, 5, :minute)})

    assert perform() == :ok
    assert_received {:ping, "/sync/fail"}
  end

  test "a cancelled sync, or one discarded before the round, doesn't fail it" do
    sync_job("cancelled", %{cancelled_at: DateTime.add(@started_at, 5, :minute)})
    sync_job("discarded", %{discarded_at: DateTime.add(@started_at, -1, :day)})

    assert perform() == :ok
    assert_received {:ping, "/sync"}
  end

  test "records the round, with what its team events and rate limits say" do
    during = DateTime.add(@started_at, 1, :minute)
    before = DateTime.add(@started_at, -1, :minute)
    Event.record!(:d4h_team_sync, data: %{outcome: "changed"}, occurred_at: during)
    Event.record!(:d4h_team_sync, data: %{outcome: "failed"}, occurred_at: during)
    Event.record!(:d4h_team_sync, data: %{outcome: "failed"}, occurred_at: before)
    Event.record!(:d4h_rate_limited, occurred_at: during)

    assert perform() == :ok

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

  test "the scheduler pings the start, and the round's end once its jobs are done" do
    ScheduleTeamSyncsWorker.perform(%Oban.Job{})

    assert_received {:ping, "/sync/start"}
    assert_received {:ping, "/sync"}
  end
end
