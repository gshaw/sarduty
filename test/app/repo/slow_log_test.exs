defmodule App.Repo.SlowLogTest do
  # The app's own SlowLog process and table, so not async.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias App.Repo
  alias App.Repo.SlowLog
  alias Ecto.Adapters.SQL.Sandbox

  @event [:app, :repo, :query]
  @five_s %{threshold: System.convert_time_unit(5_000, :millisecond, :native)}

  defp seconds(s), do: System.convert_time_unit(s, :second, :native)

  # Reports are casts to the SlowLog process; this waits until it has handled them.
  defp settle, do: :sys.get_state(SlowLog)

  defp open?(pid), do: :ets.lookup(SlowLog, pid)

  test "reports a statement over the threshold, with its caller and without params" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(
          @event,
          %{query_time: seconds(6)},
          %{query: "UPDATE oban_jobs SET state = ?", params: ["secret"], result: {:ok, nil}},
          @five_s
        )

        settle()
      end)

    assert log =~ "Repo statement held 6000 ms"
    assert log =~ "App.Repo.SlowLogTest"
    assert log =~ "UPDATE oban_jobs SET state = ?"
    refute log =~ "secret"
  end

  test "stays quiet for a statement under the threshold and a short transaction" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(@event, %{query_time: seconds(1)}, %{query: "SELECT 1"}, @five_s)
        SlowLog.handle_event(@event, %{}, %{query: "begin", result: {:ok, nil}}, @five_s)
        assert [{_pid, _began_at, false}] = open?(self())
        SlowLog.handle_event(@event, %{}, %{query: "commit"}, @five_s)
        settle()
      end)

    assert open?(self()) == []
    assert log == ""
  end

  test "tracks a real transaction from begin to commit" do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transaction(fn -> assert [{_pid, _began_at, false}] = open?(self()) end)
    end)

    assert open?(self()) == []
  end

  test "names a transaction's holder while it holds it, and its hold when it ends" do
    holder =
      spawn(fn ->
        receive do
          :commit -> SlowLog.handle_event(@event, %{}, %{query: "commit"}, @five_s)
        end
      end)

    log =
      capture_log(fn ->
        :ets.insert(SlowLog, {holder, System.monotonic_time() - seconds(6), false})
        wait_until(fn -> match?([{_pid, _began_at, true}], open?(holder)) end)
        settle()
        send(holder, :commit)
        wait_until(fn -> open?(holder) == [] end)
        settle()
      end)

    assert log =~ ~r/Repo transaction in #{inspect(holder)} open \d+ ms/
    assert log =~ "running: "
    assert log =~ "App.Repo.SlowLogTest"
    assert log =~ ~r/Repo transaction in #{inspect(holder)} held \d+ ms, then commit/
  end

  test "reports a lock error with the transactions open" do
    log =
      capture_log(fn ->
        SlowLog.handle_event(
          @event,
          %{query_time: seconds(0)},
          %{
            query: "INSERT INTO events",
            result: {:error, %Exqlite.Error{message: "Database busy"}}
          },
          @five_s
        )

        settle()
      end)

    assert log =~ "Repo lock error on INSERT INTO events | open transactions: none"
    assert log =~ "lock held by: "
  end

  test "reads the WAL lock holders of one -shm file from /proc/locks" do
    locks = """
    1: POSIX  ADVISORY  WRITE 4242 00:2a:777 120 120
    2: POSIX  ADVISORY  READ 999999999 00:2a:777 123 123
    3: POSIX  ADVISORY  WRITE 999999999 00:2a:777 121 121
    4: POSIX  ADVISORY  WRITE 999999999 00:2a:778 120 120
    5: FLOCK  ADVISORY  WRITE 999999999 00:2a:777 0 EOF
    """

    assert SlowLog.parse_locks(locks, 777, "4242") == [
             "4242 (this app) write",
             "999999999 (unknown) checkpoint"
           ]
  end

  defp wait_until(fun, tries \\ 30) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("timed out")

      true ->
        Process.sleep(100)
        wait_until(fun, tries - 1)
    end
  end
end
