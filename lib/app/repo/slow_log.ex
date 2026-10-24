defmodule App.Repo.SlowLog do
  @moduledoc """
  Names whatever holds SQLite's write lock for over 5 s, while it holds it (#416).

  Transactions are immediate, so an open one holds the write lock from `begin` to
  `commit` or `rollback`. The telemetry handler keeps each open transaction's pid in an
  ETS table, and a tick every second reports any open over 5 s with what that process is
  running at that moment. A lock error reports the transactions open, and which OS
  process holds the lock according to `/proc/locks`: this app, Litestream, or
  something else. A statement over 5 s is reported when it ends; its time includes any
  wait for the lock. A tick that runs over 2 s late means the whole VM stalled.

  Each report goes to the file set as `:file`, then to the log as a warning, then to
  Honeybadger Insights as a `repo.slow` event. The file comes first because Insights
  drops events during a lock burst, and Fly keeps only the last 100 log lines. Query
  parameters are never reported: they can hold member data. Nothing here touches the
  database.
  """

  use GenServer

  require Logger

  @event [:app, :repo, :query]
  @handler_id "sarduty-repo-slow-log"
  @table __MODULE__
  @threshold_ms 5_000
  @tick_ms 1_000
  @late_ms 2_000
  # SQLite's unix VFS locks these bytes of the -shm file for the WAL's write,
  # checkpoint, and recovery locks.
  @lock_bytes %{"120" => "write", "121" => "checkpoint", "122" => "recovery"}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    threshold = System.convert_time_unit(@threshold_ms, :millisecond, :native)

    # A restart attaches again; a handler that raised was detached by :telemetry.
    :telemetry.detach(@handler_id)

    :ok =
      :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, %{threshold: threshold})

    state = %{
      threshold: threshold,
      file: Application.get_env(:sarduty, __MODULE__, [])[:file],
      database: Application.get_env(:sarduty, App.Repo)[:database],
      last_lock_error: nil
    }

    {:ok, schedule_tick(state)}
  end

  # Telemetry runs a handler in the process that ran the query, so `self()` is the
  # transaction's owner. A handler must never raise, or :telemetry detaches it.
  def handle_event(@event, _measurements, %{query: "begin", result: {:ok, _}}, _config) do
    safe_ets(fn -> :ets.insert(@table, {self(), System.monotonic_time(), false}) end)
  end

  def handle_event(@event, _measurements, %{query: query}, _config)
      when query in ["commit", "rollback"] do
    case safe_ets(fn -> :ets.take(@table, self()) end) do
      [{_pid, began_at, true}] ->
        GenServer.cast(__MODULE__, {:released, self(), ms_since(began_at), query})

      _ ->
        :ok
    end
  end

  def handle_event(@event, measurements, %{query: query} = metadata, %{threshold: threshold}) do
    query = query |> to_string() |> String.slice(0, 200)
    if lock_error?(metadata[:result]), do: GenServer.cast(__MODULE__, {:lock_error, query})

    duration = Map.get(measurements, :query_time, 0)

    if duration > threshold do
      ms = System.convert_time_unit(duration, :native, :millisecond)
      GenServer.cast(__MODULE__, {:slow_statement, ms, caller(), query})
    end

    :ok
  end

  @impl GenServer
  def handle_cast({:slow_statement, ms, caller, query}, state) do
    report(state, "Repo statement held #{ms} ms: #{caller} | #{query}")
    {:noreply, state}
  end

  def handle_cast({:released, pid, ms, query}, state) do
    report(state, "Repo transaction in #{inspect(pid)} held #{ms} ms, then #{query}")
    {:noreply, state}
  end

  # One report per 5 s: a burst brings several errors at once.
  def handle_cast({:lock_error, query}, state) do
    now = System.monotonic_time()

    if state.last_lock_error && now - state.last_lock_error < state.threshold do
      {:noreply, state}
    else
      open =
        for {pid, began_at, _reported} <- :ets.tab2list(@table) do
          "#{inspect(pid)} for #{ms_since(began_at)} ms"
        end

      report(
        state,
        "Repo lock error on #{query} | open transactions: #{join_or_none(open)} | " <>
          "lock held by: #{state.database |> lock_holders() |> join_or_none()}"
      )

      {:noreply, %{state | last_lock_error: now}}
    end
  end

  @impl GenServer
  def handle_info(:tick, state) do
    late_ms = ms_since(state.tick_due)

    if late_ms > @late_ms,
      do: report(state, "Repo slow log tick ran #{late_ms} ms late: the VM stalled")

    now = System.monotonic_time()

    for {pid, began_at, false} <- :ets.tab2list(@table), now - began_at > state.threshold do
      if Process.alive?(pid) do
        :ets.update_element(@table, pid, {3, true})
        report(state, holder_report(pid, ms_since(began_at), state.database))
      else
        :ets.delete(@table, pid)
      end
    end

    {:noreply, schedule_tick(state)}
  end

  @doc "A transaction open too long: who holds it, and what it is running right now."
  def holder_report(pid, ms, database) do
    stack =
      case Process.info(pid, :current_stacktrace) do
        {:current_stacktrace, frames} ->
          frames |> Enum.take(12) |> Enum.map_join(" < ", &Exception.format_stacktrace_entry/1)

        nil ->
          "exited"
      end

    "Repo transaction in #{inspect(pid)} open #{ms} ms, running: #{stack} | " <>
      "lock held by: #{database |> lock_holders() |> join_or_none()}"
  end

  @doc """
  The OS processes holding the WAL's locks on `database`, from `/proc/locks`. Empty
  where there is no `/proc`, as on a Mac.
  """
  def lock_holders(nil), do: []

  def lock_holders(database) do
    with {:ok, %{inode: inode}} <- File.stat(database <> "-shm"),
         {:ok, locks} <- File.read("/proc/locks") do
      parse_locks(locks, inode, System.pid())
    else
      _ -> []
    end
  end

  @doc "Lines of `/proc/locks` on the -shm file's WAL lock bytes, as `pid name lock`."
  def parse_locks(locks, inode, own_pid) do
    for line <- String.split(locks, "\n"),
        [_n, "POSIX", _advisory, _mode, pid, device, start | _] <- [String.split(line)],
        String.ends_with?(device, ":#{inode}"),
        lock when lock != nil <- [@lock_bytes[start]] do
      "#{pid} #{process_name(pid, own_pid)} #{lock}"
    end
  end

  defp process_name(own_pid, own_pid), do: "(this app)"

  defp process_name(pid, _own_pid) do
    case File.read("/proc/#{pid}/comm") do
      {:ok, name} -> "(#{String.trim(name)})"
      _ -> "(unknown)"
    end
  end

  defp report(state, message) do
    if state.file do
      line = [DateTime.utc_now() |> DateTime.to_iso8601(), " ", message, "\n"]
      File.write(state.file, line, [:append])
    end

    Logger.warning(message)
    Honeybadger.event("repo.slow", %{message: message})
  end

  defp schedule_tick(state) do
    Process.send_after(self(), :tick, @tick_ms)
    Map.put(state, :tick_due, System.monotonic_time() + ms_to_native(@tick_ms))
  end

  defp lock_error?({:error, %Exqlite.Error{message: message}}) when is_binary(message),
    do: String.contains?(message, ["busy", "locked"])

  defp lock_error?(_result), do: false

  defp safe_ets(fun) do
    fun.()
  rescue
    ArgumentError -> :ok
  end

  defp join_or_none([]), do: "none"
  defp join_or_none(items), do: Enum.join(items, ", ")

  defp ms_since(began_at),
    do: System.convert_time_unit(System.monotonic_time() - began_at, :native, :millisecond)

  defp ms_to_native(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  # The innermost few frames of our code or Oban's, which made the call; the Repo,
  # Ecto, and this module sit above them. With none, the process's first frame.
  defp caller do
    {:current_stacktrace, frames} = Process.info(self(), :current_stacktrace)

    case frames |> Enum.filter(&caller_frame?/1) |> Enum.take(3) do
      [] -> frames |> List.last() |> Exception.format_stacktrace_entry()
      ours -> Enum.map_join(ours, " < ", &Exception.format_stacktrace_entry/1)
    end
  end

  defp caller_frame?({module, _fun, _arity, _location}) do
    name = inspect(module)

    module not in [__MODULE__, App.Repo, Oban.Repo] and
      Enum.any?(["App.", "Web.", "Oban."], &String.starts_with?(name, &1))
  end
end
