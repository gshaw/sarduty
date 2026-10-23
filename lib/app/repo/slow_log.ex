defmodule App.Repo.SlowLog do
  @moduledoc """
  Logs any `App.Repo` transaction that holds the database for over 5 s, and any
  statement that runs over 5 s, with the code that called it (#416).

  Transactions are immediate, so one holds SQLite's write lock from `begin` to `commit`
  or `rollback`, and every other write waits. A statement's time includes its own wait
  for the lock, so a slow statement is either slow itself or waiting for a holder.

  Each goes to the log as a warning and to Honeybadger Insights as a `repo.slow` event,
  without the query's parameters, which can hold member data. Keep it after #416 is
  fixed: a 5 s hold is worth knowing about whatever causes it, and it costs nothing
  until one happens.
  """

  require Logger

  @event [:app, :repo, :query]
  @begin_key {__MODULE__, :begun_at}
  @threshold_ms 5_000

  def attach(threshold_ms \\ @threshold_ms) do
    :telemetry.attach(
      "sarduty-repo-slow-log",
      @event,
      &__MODULE__.handle_event/4,
      %{threshold: System.convert_time_unit(threshold_ms, :millisecond, :native)}
    )
  end

  # Telemetry runs a handler in the process that ran the query, so the process
  # dictionary holds when its transaction began.
  def handle_event(@event, _measurements, %{query: "begin", result: {:ok, _}}, _config) do
    Process.put(@begin_key, System.monotonic_time())
    :ok
  end

  def handle_event(@event, _measurements, %{query: query}, config)
      when query in ["commit", "rollback"] do
    case Process.delete(@begin_key) do
      nil -> :ok
      begun_at -> maybe_report(:transaction, System.monotonic_time() - begun_at, query, config)
    end
  end

  def handle_event(@event, measurements, %{query: query}, config) do
    maybe_report(:statement, Map.get(measurements, :query_time, 0), query, config)
  end

  defp maybe_report(kind, duration, query, %{threshold: threshold}) when duration > threshold do
    ms = System.convert_time_unit(duration, :native, :millisecond)
    caller = caller()
    query = query |> to_string() |> String.slice(0, 200)

    Logger.warning("Repo #{kind} held #{ms} ms: #{caller} | #{query}")

    Honeybadger.event("repo.slow", %{
      kind: kind,
      duration_ms: ms,
      caller: caller,
      query: query
    })
  end

  defp maybe_report(_kind, _duration, _query, _config), do: :ok

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
