defmodule App.Ops.Query do
  @moduledoc """
  Runs one SQL statement on its own read-only connection to the database, so a write
  fails however it's written. It stops at 10 s, before a heavy query drains the shared
  CPU, and prints at most 50 rows: aggregate in SQL.
  """

  use App.Ops.Task,
    name: "query",
    usage: "query SQL",
    summary: "Read-only SQL. Stops at 10 s, prints 50 rows. Aggregate in SQL."

  alias Exqlite.Sqlite3

  @timeout_ms 10_000
  @max_rows 50

  @impl App.Ops.Task
  def run([sql]), do: query(sql, @timeout_ms)
  def run(_args), do: {:error, "Give one SQL statement, in quotes."}

  @doc "Runs `sql` with a time limit; tests pass a short one."
  def query(sql, timeout_ms) do
    case Sqlite3.open(App.Repo.config()[:database], mode: :readonly) do
      {:ok, db} ->
        try do
          :ok = Sqlite3.set_busy_timeout(db, 2_000)
          db |> prepare(sql, timeout_ms) |> result(timeout_ms)
        after
          Sqlite3.close(db)
        end

      {:error, reason} ->
        {:error, "The database didn't open: #{reason}"}
    end
  end

  defp prepare(db, sql, timeout_ms) do
    case Sqlite3.prepare(db, sql) do
      {:ok, statement} ->
        try do
          {:ok, columns} = Sqlite3.columns(db, statement)
          {columns, fetch(db, statement, timeout_ms)}
        after
          Sqlite3.release(db, statement)
        end

      {:error, reason} ->
        {[], {:error, reason}}
    end
  end

  # One more row than it prints, to know there were more. SQLite stops a statement at its
  # next step once interrupted; the connection stays open until the step returns.
  defp fetch(db, statement, timeout_ms) do
    task = Task.async(fn -> Sqlite3.multi_step(db, statement, @max_rows + 1) end)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        result

      nil ->
        Sqlite3.interrupt(db)
        Task.await(task, :infinity)
        :timeout
    end
  end

  defp result({_columns, {:error, reason}}, _timeout_ms), do: {:error, reason}
  defp result({_columns, :busy}, _timeout_ms), do: {:error, "The database was busy. Try again."}

  defp result({_columns, :timeout}, timeout_ms) do
    limit = Service.Format.run_time(timeout_ms)
    {:error, "Stopped at the #{limit} limit. Aggregate in SQL, or narrow it."}
  end

  defp result({columns, {_rows_or_done, rows}}, _timeout_ms) when length(rows) > @max_rows do
    note = "Stopped at #{@max_rows} rows. Aggregate in SQL, or add a limit."
    {:ok, %{columns: columns, rows: Enum.take(rows, @max_rows), note: note}}
  end

  defp result({columns, {_rows_or_done, rows}}, _timeout_ms),
    do: {:ok, %{columns: columns, rows: rows}}
end
