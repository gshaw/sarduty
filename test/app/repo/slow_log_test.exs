defmodule App.Repo.SlowLogTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias App.Repo.SlowLog

  @event [:app, :repo, :query]
  @five_s %{threshold: System.convert_time_unit(5_000, :millisecond, :native)}

  defp seconds(s), do: System.convert_time_unit(s, :second, :native)

  test "logs a statement over the threshold, with its caller and without params" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(
          @event,
          %{query_time: seconds(6)},
          %{query: "UPDATE oban_jobs SET state = ?", params: ["secret"], result: {:ok, nil}},
          @five_s
        )
      end)

    assert log =~ "Repo statement held 6000 ms"
    assert log =~ "App.Repo.SlowLogTest"
    assert log =~ "UPDATE oban_jobs SET state = ?"
    refute log =~ "secret"
  end

  test "stays quiet for a statement under the threshold" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(@event, %{query_time: seconds(1)}, %{query: "SELECT 1"}, @five_s)
      end)

    assert log == ""
  end

  test "logs a transaction held from begin to commit over the threshold" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(@event, %{}, %{query: "begin", result: {:ok, nil}}, @five_s)
        SlowLog.handle_event(@event, %{}, %{query: "commit"}, %{threshold: -1})
      end)

    assert log =~ "Repo transaction held"
    assert log =~ "| commit"
  end

  test "stays quiet for a short transaction, and for a commit without a begin" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(@event, %{}, %{query: "begin", result: {:ok, nil}}, @five_s)
        SlowLog.handle_event(@event, %{}, %{query: "rollback"}, @five_s)
        SlowLog.handle_event(@event, %{}, %{query: "commit"}, %{threshold: -1})
      end)

    assert log == ""
  end
end
