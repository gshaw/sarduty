defmodule App.Operation.RestoreTeam do
  @moduledoc """
  Puts a deleted team back from the database copy App.Operation.DeleteTeam took first.
  Run by hand on the machine (docs/deployment.md); there is no page for it.

  It copies the team's rows, as DeleteTeam.scopes/2 finds them in the copy, back into
  the live database with their own ids. Every table uses AUTOINCREMENT, so a deleted id
  is never given to a new row. Columns added since the copy take their defaults; a table
  added since has no rows to restore. Keys are checked at commit, so a row that points
  at something gone since, such as a deleted login, fails the whole restore.

  The team's logo comes back with its next refresh.
  """

  alias App.Operation.DeleteTeam
  alias App.Repo

  @doc """
  Restores team `team_id` from the copy at `path`. Returns `{:ok, rows}`, the rows put
  back per table, or `{:error, reason}` with nothing changed.
  """
  def call(path, team_id) when is_binary(path) and is_integer(team_id) do
    if File.exists?(path) do
      # ATTACH can't run in a transaction, and it holds only for one connection.
      Repo.checkout(fn ->
        Repo.query!("ATTACH DATABASE ? AS copy", [path])

        try do
          restore(team_id)
        after
          Repo.query!("DETACH DATABASE copy")
        end
      end)
    else
      {:error, "no copy at #{path}"}
    end
  end

  defp restore(team_id) do
    case check(team_id) do
      :ok ->
        Repo.transaction(fn ->
          Repo.query!("PRAGMA defer_foreign_keys = ON")
          copy_rows(team_id)
        end)

      error ->
        error
    end
  end

  # The copy must have the team, and the live database must not: a team signed up again
  # since holds its D4H team id and subdomain.
  defp check(team_id) do
    %{rows: copy} =
      Repo.query!("SELECT d4h_team_id, subdomain FROM copy.teams WHERE id = ?", [team_id])

    case copy do
      [] ->
        {:error, "the copy has no team #{team_id}"}

      [[d4h_team_id, subdomain]] ->
        %{rows: [[live]]} =
          Repo.query!(
            "SELECT count(*) FROM main.teams WHERE id = ? OR d4h_team_id = ? OR subdomain = ?",
            [team_id, d4h_team_id, subdomain]
          )

        if live == 0, do: :ok, else: {:error, "a team with its id, D4H id, or subdomain is live"}
    end
  end

  # Parents first, the reverse of the delete.
  defp copy_rows(team_id) do
    copy_tables = tables("copy")

    for {table, where} <- team_id |> DeleteTeam.scopes("copy") |> Enum.reverse(),
        table in copy_tables,
        into: %{} do
      columns = table |> shared_columns() |> Enum.map_join(", ", &~s|"#{&1}"|)

      %{num_rows: count} =
        Repo.query!(
          ~s|INSERT INTO main."#{table}" (#{columns}) SELECT #{columns} FROM copy."#{table}" WHERE #{where}|
        )

      {table, count}
    end
    |> Map.reject(fn {_table, count} -> count == 0 end)
  end

  defp tables(schema) do
    %{rows: rows} =
      Repo.query!(~s|SELECT name FROM "#{schema}".sqlite_master WHERE type = 'table'|)

    MapSet.new(rows, &hd/1)
  end

  defp shared_columns(table) do
    %{rows: rows} =
      Repo.query!(
        "SELECT name FROM pragma_table_info(?, 'main') INTERSECT SELECT name FROM pragma_table_info(?, 'copy')",
        [table, table]
      )

    Enum.map(rows, &hd/1)
  end
end
