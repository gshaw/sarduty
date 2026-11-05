defmodule App.Operation.DeleteTeam do
  @moduledoc """
  Deletes a team and every row SAR Duty holds for it, from a SAR Duty admin's team page.
  Nothing in D4H or Records changes. The admin types the team's name to confirm.

  Which rows go is read from the database's foreign keys, not a list kept by hand: a row
  goes when it has the team's `team_id`, or a key that points at a row that goes. Keys
  that set null on delete, such as a user's last team, don't count. Foreign keys are
  checked at commit, so a table the walk misses fails the delete instead of leaving rows
  behind.

  Before deleting, it copies the team's rows to a file beside the database, so
  App.Operation.RestoreTeam can undo a mistake for 7 days. The file has every table, and
  in them only this team's rows. App.Worker.PruneEventsWorker deletes older copies.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.NotifyTeamDeletedWorker

  require Logger

  @snapshot_days 7

  def snapshot_days, do: @snapshot_days

  @doc "Whether `typed` is the team's name, ignoring case and spaces at either end."
  def name_matches?(%Team{name: name}, typed) when is_binary(typed),
    do: comparable(typed) == comparable(name)

  def name_matches?(_team, _typed), do: false

  defp comparable(name), do: name |> String.trim() |> String.downcase()

  @doc """
  Deletes the team when `typed` matches its name. Returns `{:ok, snapshot_path}`, nil
  when snapshots are off (tests), or `{:error, :name_mismatch}`.
  """
  def call(%Team{} = team, typed, %User{is_admin: true} = admin) do
    if name_matches?(team, typed) do
      snapshot = take_snapshot(team)
      counts = row_counts(team)

      # A key the walk missed fails the commit, and nothing is deleted.
      {:ok, _job} =
        Repo.transaction(fn ->
          delete_rows(team)
          cancel_jobs(team)

          Event.record!(:team_deleted,
            user_id: admin.id,
            data: %{
              team_id: team.id,
              d4h_team_id: team.d4h_team_id,
              subdomain: team.subdomain,
              rows: Enum.sum(Map.values(counts))
            }
          )

          NotifyTeamDeletedWorker.enqueue(team, admin, snapshot)
        end)

      remove_logo(team)
      Logger.info("Deleted team #{team.id} (#{team.subdomain}); snapshot #{snapshot}")
      {:ok, snapshot}
    else
      {:error, :name_mismatch}
    end
  end

  @doc "Rows that go with the team, per table, leaving out tables with none."
  def row_counts(%Team{id: team_id}) do
    for {table, where} <- scopes(team_id), into: %{} do
      %{rows: [[count]]} = Repo.query!(~s|SELECT count(*) FROM "#{table}" WHERE #{where}|)
      {table, count}
    end
    |> Map.reject(fn {_table, count} -> count == 0 end)
  end

  # Children before parents, so each table's WHERE still finds its parents' rows.
  # defer_foreign_keys holds the checks to commit, when every row is gone.
  defp delete_rows(%Team{id: team_id}) do
    Repo.query!("PRAGMA defer_foreign_keys = ON")

    for {table, where} <- scopes(team_id) do
      Repo.query!(~s|DELETE FROM "#{table}" WHERE #{where}|)
    end
  end

  # Jobs waiting to run for the team. One running now finds the team gone.
  defp cancel_jobs(%Team{id: team_id}) do
    Repo.query!(
      "DELETE FROM oban_jobs WHERE state IN ('available', 'scheduled', 'retryable') AND json_extract(args, '$.team_id') = ?",
      [team_id]
    )
  end

  @doc """
  Each table that holds the team's rows, with the WHERE that finds them, children first
  and `teams` last. The WHERE reads the tables in `schema`: "main", or an attached copy
  for App.Operation.RestoreTeam. The tables come from this database's keys.
  """
  def scopes(team_id, schema \\ "main") when is_integer(team_id) do
    keys = foreign_keys()
    with_team_id = keys |> Map.keys() |> Enum.filter(&team_id_column?/1) |> MapSet.new()
    in_scope = keys |> reach(MapSet.new(["teams"])) |> MapSet.union(with_team_id)

    for table <- order(in_scope, keys, with_team_id),
        do: {table, where(table, {team_id, schema}, keys, with_team_id, in_scope, MapSet.new())}
  end

  # Every table, with its foreign keys that delete with or block their parent.
  defp foreign_keys do
    %{rows: rows} =
      Repo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
      )

    for [table] <- rows, into: %{} do
      %{rows: fks} =
        Repo.query!(~s|SELECT "table", "from", "to", on_delete FROM pragma_foreign_key_list(?)|, [
          table
        ])

      {table,
       for(
         [parent, column, to, on_delete] <- fks,
         on_delete != "SET NULL",
         do: {column, parent, to}
       )}
    end
  end

  defp team_id_column?(table) do
    %{rows: rows} =
      Repo.query!("SELECT count(*) FROM pragma_table_info(?) WHERE name = 'team_id'", [table])

    rows == [[1]]
  end

  # Tables whose keys lead, step by step, to `teams`.
  defp reach(keys, found) do
    more =
      for {table, fks} <- keys,
          table not in found,
          Enum.any?(fks, fn {_column, parent, _to} -> parent in found end),
          into: found,
          do: table

    if MapSet.size(more) == MapSet.size(found), do: found, else: reach(keys, more)
  end

  defp where("teams", {team_id, _schema}, _keys, _with_team_id, _in_scope, _seen),
    do: "id = #{team_id}"

  defp where(table, {team_id, schema} = team, keys, with_team_id, in_scope, seen) do
    if table in with_team_id do
      "team_id = #{team_id}"
    else
      seen = MapSet.put(seen, table)

      keys
      |> Map.fetch!(table)
      |> Enum.filter(fn {_column, parent, _to} -> parent in in_scope and parent not in seen end)
      |> Enum.map(fn {column, parent, to} ->
        parent_where = where(parent, team, keys, with_team_id, in_scope, seen)
        ~s|"#{column}" IN (SELECT "#{to}" FROM "#{schema}"."#{parent}" WHERE #{parent_where})|
      end)
      |> or_clauses()
    end
  end

  defp or_clauses([]), do: "0"
  defp or_clauses(clauses), do: Enum.join(clauses, " OR ")

  # Tables found through a parent go first, deepest first: their WHERE reads the parent.
  # Tables with team_id read nothing else, and `teams` goes last.
  defp order(in_scope, keys, with_team_id) do
    through_parent = in_scope |> MapSet.delete("teams") |> MapSet.difference(with_team_id)
    direct = in_scope |> MapSet.delete("teams") |> MapSet.intersection(with_team_id)

    Enum.concat([
      children_first(Enum.sort(through_parent), keys, []),
      Enum.sort(direct),
      ["teams"]
    ])
  end

  defp children_first([], _keys, done), do: Enum.reverse(done)

  defp children_first(left, keys, done) do
    # A table is ready when no table still left reads it.
    ready =
      Enum.reject(left, fn table -> Enum.any?(left -- [table], &reads?(keys, &1, table)) end)

    # A cycle: take the rest in name order, and leave it to the commit's check.
    ready = if ready == [], do: left, else: ready
    children_first(left -- ready, keys, Enum.reverse(ready) ++ done)
  end

  defp reads?(keys, child, parent), do: Enum.any?(keys[child], &(elem(&1, 1) == parent))

  # The team's rows, before anything is deleted. VACUUM INTO can't run in a
  # transaction, so tests, which run in one, set no directory.
  defp take_snapshot(%Team{} = team) do
    case snapshot_dir() do
      nil ->
        nil

      dir ->
        File.mkdir_p!(dir)
        stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
        path = Path.join(dir, "#{team.subdomain}-#{stamp}.db")
        Repo.query!("VACUUM INTO ?", [path])
        keep_only_team(path, team.id)
        path
    end
  end

  @doc """
  Empties every table in the database file at `path` but for team `team_id`'s rows, then
  vacuums it, so no other team's data is left even in its free pages. Public for the
  check that a copy holds only its team.
  """
  def keep_only_team(path, team_id) do
    scopes = scopes(team_id, "copy")

    # coalesce: a NULL team_id or key makes the WHERE NULL, and NOT NULL keeps the row.
    # Keys are off on this connection while it works: a team's row may name a login the
    # copy no longer has, and RestoreTeam puts it back beside the live one.
    Repo.checkout(fn ->
      Repo.query!("PRAGMA foreign_keys = OFF")
      Repo.query!("ATTACH DATABASE ? AS copy", [path])

      try do
        {:ok, _done} =
          Repo.transaction(fn ->
            for table <- copy_tables() do
              case List.keyfind(scopes, table, 0) do
                {^table, where} ->
                  Repo.query!(~s|DELETE FROM copy."#{table}" WHERE NOT coalesce(#{where}, 0)|)

                nil ->
                  Repo.query!(~s|DELETE FROM copy."#{table}"|)
              end
            end
          end)

        Repo.query!("VACUUM copy")
      after
        Repo.query!("DETACH DATABASE copy")
        Repo.query!("PRAGMA foreign_keys = ON")
      end
    end)
  end

  # sqlite_sequence keeps only each table's last id, which a restore doesn't read.
  defp copy_tables do
    %{rows: rows} =
      Repo.query!(
        "SELECT name FROM copy.sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
      )

    Enum.map(rows, &hd/1)
  end

  defp snapshot_dir, do: Application.get_env(:sarduty, __MODULE__, [])[:snapshot_dir]

  @doc "Deletes snapshots older than #{@snapshot_days} days. Returns how many."
  def prune_snapshots(now) do
    case snapshot_dir() do
      nil ->
        0

      dir ->
        cutoff = now |> DateTime.add(-@snapshot_days, :day) |> DateTime.to_unix()

        dir
        |> Path.join("*.db")
        |> Path.wildcard()
        |> Enum.filter(fn path -> File.stat!(path, time: :posix).mtime < cutoff end)
        |> Enum.map(&File.rm!/1)
        |> length()
    end
  end

  defp remove_logo(%Team{subdomain: subdomain}) do
    _ignored = subdomain |> Team.logo_path() |> File.rm()
    :ok
  rescue
    # No TEAM_LOGO_PATH, as in some test runs.
    _error -> :ok
  end
end
