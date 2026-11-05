defmodule App.Operation.DeleteTeam do
  @moduledoc """
  The one place a team's rows are deleted. A SAR Duty admin's Delete team (`call/3`)
  uses it now; Try a demo (#857) and a team closing its own account call `purge/2` too.

  Every table with a `team_id` is in @team_tables, and every table whose rows hang off
  one of those without a `team_id` of its own is in @child_tables. DeleteTeamTest fails
  when a migration adds a table to neither, so a new table can't leave rows behind. It
  runs in one transaction with foreign keys checked at commit, so a row missed still
  rolls the whole delete back.

  Users stay: a user is only an email and may be on another team (#890 prunes logins
  that reach no team). Nothing in D4H changes. A team on SAR Duty Records goes from
  Records too: Records switches it off at once and deletes it 7 days on, so a Records
  admin can switch it back on until then (App.Adapter.D4H.delete_records_team/1).

  `snapshot: true` first copies the team's rows to a file beside the database, so
  App.Operation.RestoreTeam can undo a mistake for 7 days. The file has every table, and
  in them only this team's rows (`write_copy/3`). App.Worker.PruneEventsWorker deletes older copies.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo
  alias App.Worker.NotifyTeamDeletedWorker
  alias Exqlite.Sqlite3

  require Logger

  @snapshot_days 7

  @team_tables ~w(activities activity_updates agent_connections attendance_scans
                  attention_snoozes certificates change_set_rows change_sets chore_categories
                  chore_events chores custom_fields d4h_changes endorsements equipment_items
                  equipment_usages events group_membership_changes group_rules groups
                  home_coordinates location_bookmarks mcp_calls member_away_periods member_cards
                  member_check_ins member_standing_changes members no_shows qualifications
                  reminders reports route_distances tags team_login_grants templates trips
                  whiteboard_notes)

  # Table, its key, and the team table that key points at.
  @child_tables [
    {"attendances", "activity_id", "activities"},
    {"attendances", "member_id", "members"},
    {"group_members", "group_id", "groups"},
    {"group_members", "member_id", "members"},
    {"member_qualification_awards", "member_id", "members"},
    {"member_qualification_awards", "qualification_id", "qualifications"},
    {"tax_credit_letters", "member_id", "members"},
    {"endorsement_includes", "endorsement_id", "endorsements"},
    {"endorsement_includes", "included_endorsement_id", "endorsements"},
    {"endorsement_qualifications", "endorsement_id", "endorsements"},
    {"group_rule_references", "endorsement_id", "endorsements"},
    {"group_rule_references", "group_rule_id", "group_rules"},
    {"chore_category_tags", "chore_category_id", "chore_categories"},
    {"chore_category_tags", "tag_id", "tags"},
    {"template_groups", "group_id", "groups"},
    {"template_groups", "template_id", "templates"},
    {"template_items", "equipment_item_id", "equipment_items"},
    {"template_items", "template_id", "templates"},
    {"template_tags", "tag_id", "tags"},
    {"template_tags", "template_id", "templates"},
    {"certificate_files", "certificate_id", "certificates"},
    {"pass_registrations", "member_card_id", "member_cards"},
    {"report_versions", "report_id", "reports"}
  ]

  @doc false
  def team_tables, do: @team_tables

  @doc false
  def child_tables, do: @child_tables

  def snapshot_days, do: @snapshot_days

  @doc """
  A SAR Duty admin's delete: when `typed` matches the team's name, deletes it with a
  snapshot and emails every SAR Duty admin. `{:ok, result}` as `purge/2` gives it,
  `{:error, :name_mismatch}`, or `purge/2`'s error with nothing deleted.
  """
  def call(%Team{} = team, typed, %User{is_admin: true} = admin) do
    if Team.name_matches?(team, typed) do
      with {:ok, %{snapshot: snapshot}} = result <-
             purge(team, reason: :admin, by: admin, snapshot: true) do
        NotifyTeamDeletedWorker.enqueue(team, admin, snapshot)
        result
      end
    else
      {:error, :name_mismatch}
    end
  end

  @doc """
  Deletes the team and every row SAR Duty holds for it, cancels its waiting jobs, and
  records a `team_deleted` event, in one transaction; then removes its logo. A team on
  SAR Duty Records is deleted there first, after the snapshot, so a refusal deletes
  nothing.

  - `reason:` why, kept in the event: `:admin`
  - `by:` the user who deleted it, or nil
  - `snapshot:` true copies the team's rows first (nil when no directory is set, as in
    tests)

  Returns `{:ok, %{rows: count, snapshot: path_or_nil}}`, or `{:error, %D4H.Error{}}`
  when Records refused. Each caller tells its own people.
  """
  def purge(%Team{} = team, opts) do
    snapshot = if Keyword.get(opts, :snapshot, false), do: take_snapshot(team)

    case delete_in_records(team) do
      :ok ->
        delete(team, snapshot, opts)

      {:error, _error} = error ->
        if snapshot, do: File.rm(snapshot)
        error
    end
  end

  defp delete_in_records(team),
    do: if(D4H.records?(team), do: D4H.delete_records_team(team), else: :ok)

  defp delete(team, snapshot, opts) do
    reason = Keyword.fetch!(opts, :reason)
    by = Keyword.get(opts, :by)
    rows = team |> row_counts() |> Map.values() |> Enum.sum()

    # A table missing from the lists fails the commit, and nothing is deleted.
    {:ok, _event} =
      Repo.transaction(fn ->
        delete_rows(team)
        cancel_jobs(team)

        Event.record!(:team_deleted,
          user_id: by && by.id,
          data: %{
            reason: reason,
            team_id: team.id,
            d4h_team_id: team.d4h_team_id,
            subdomain: team.subdomain,
            records: D4H.records?(team),
            rows: rows
          }
        )
      end)

    remove_logo(team)
    Logger.info("Deleted team #{team.id} (#{team.subdomain}), #{reason}; snapshot #{snapshot}")
    {:ok, %{rows: rows, snapshot: snapshot}}
  end

  @doc "Rows that go with the team, per table, leaving out tables with none."
  def row_counts(%Team{id: team_id}) do
    for {table, where} <- scopes(team_id), into: %{} do
      %{rows: [[count]]} = Repo.query!(~s|SELECT count(*) FROM "#{table}" WHERE #{where}|)
      {table, count}
    end
    |> Map.reject(fn {_table, count} -> count == 0 end)
  end

  @doc """
  Each table that holds the team's rows, with the WHERE that finds them: child tables
  first, so their WHERE still finds the parents, then team tables, and `teams` last.
  The WHERE reads parents in `schema`: "main", or an attached copy for
  App.Operation.RestoreTeam and the snapshot.
  """
  def scopes(team_id, schema \\ "main") when is_integer(team_id) do
    children =
      @child_tables
      |> Enum.group_by(&elem(&1, 0), fn {_table, key, parent} ->
        ~s|"#{key}" IN (SELECT id FROM "#{schema}"."#{parent}" WHERE team_id = #{team_id})|
      end)
      |> Enum.sort()
      |> Enum.map(fn {table, clauses} -> {table, Enum.join(clauses, " OR ")} end)

    Enum.concat([
      children,
      Enum.map(@team_tables, &{&1, "team_id = #{team_id}"}),
      [{"teams", "id = #{team_id}"}]
    ])
  end

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

  # The team's rows, before anything is deleted. Tests set no directory: the copy reads
  # the database file on its own connection, which can't see a test's sandbox rows.
  defp take_snapshot(%Team{} = team) do
    case snapshot_dir() do
      nil ->
        nil

      dir ->
        File.mkdir_p!(dir)
        stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
        path = Path.join(dir, "#{team.subdomain}-#{stamp}.db")
        write_copy(path, Repo.config()[:database], team.id)
        path
    end
  end

  @doc """
  Writes team `team_id`'s rows from the database file at `source` to a new file at
  `path`: every table, and in them only this team's rows, as `scopes/2` finds them.

  It works on a connection of its own, not the Repo's, so it takes none of the app's
  connections and holds no write lock: one read transaction over the live file, and
  writes only to the new one. It reads only the team's rows, so a small team's copy is
  quick however big the database is, and no other team's data is ever written. Keys
  are off on this connection: a row may name a login the copy has no table rows for.
  A failure removes the file and raises.
  """
  def write_copy(path, source, team_id) when is_integer(team_id) do
    {:ok, db} = Sqlite3.open(path)

    try do
      copy_rows(db, source, team_id)
      :ok = Sqlite3.close(db)
    rescue
      error ->
        Sqlite3.close(db)
        File.rm(path)
        reraise error, __STACKTRACE__
    end
  end

  # One read transaction over the live file, so every table is read as of one moment.
  defp copy_rows(db, source, team_id) do
    exec!(db, "PRAGMA busy_timeout = 30000")
    exec!(db, "ATTACH DATABASE '#{String.replace(source, "'", "''")}' AS live")
    exec!(db, "BEGIN")

    for sql <- table_sql(db), do: exec!(db, sql)

    for {table, where} <- scopes(team_id, "live") do
      exec!(db, ~s|INSERT INTO main."#{table}" SELECT * FROM live."#{table}" WHERE #{where}|)
    end

    exec!(db, "COMMIT")
    exec!(db, "DETACH DATABASE live")
  end

  # Every table's CREATE statement in the live database. sqlite_sequence comes with the
  # first AUTOINCREMENT table.
  defp table_sql(db) do
    {:ok, statement} =
      Sqlite3.prepare(
        db,
        "SELECT sql FROM live.sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      )

    {:ok, rows} = Sqlite3.fetch_all(db, statement)
    :ok = Sqlite3.release(db, statement)
    Enum.map(rows, &hd/1)
  end

  defp exec!(db, sql) do
    case Sqlite3.execute(db, sql) do
      :ok -> :ok
      {:error, reason} -> raise "Copying the team failed: #{reason}\n#{sql}"
    end
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
