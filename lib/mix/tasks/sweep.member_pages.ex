defmodule Mix.Tasks.Sweep.MemberPages do
  @shortdoc "Opens every member page as every member, in a copy of a database"

  @moduledoc """
  Opens every page a member sees, as every member, and lists the pages that crash (#425).
  It finds the member whose data breaks a page, without anyone clicking through.

      mix sweep.member_pages --db ~/Developer/sarduty/db/sarduty_dev.db
      mix sweep.member_pages --db PATH --team SUBDOMAIN

  It copies the database to the temp directory and runs
  `test/web/member_pages_sweep_test.exs` against the copy, which a team admin views as
  each member (#425): the Dashboard, Activities, Your membership, every year page,
  Contact details, and every tax credit letter PDF. The copy is migrated and deleted
  afterwards, and the test runs in the Ecto sandbox, so nothing is written to the
  database you name. D4H and Mapbox answer 404, as they do in tests, so nothing leaves
  the machine.

  The output names teams by subdomain and members by local id, never by name. It exits
  non-zero when a page fails.

  Options:

    * `--db` - the SQLite database to copy. Defaults to `db/sarduty_dev.db`.
    * `--team` - one team's subdomain. Defaults to every team.
  """
  use Mix.Task

  @test_file "test/web/member_pages_sweep_test.exs"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [db: :string, team: :string])
    source = Path.expand(opts[:db] || "db/sarduty_dev.db")
    if !File.regular?(source), do: Mix.raise("No database at #{source}. Pass --db PATH.")

    copy = Path.join(System.tmp_dir!(), "sarduty-sweep-#{System.unique_integer([:positive])}.db")

    try do
      copy!(source, copy)
      Mix.shell().info("Sweeping a copy of #{source}")
      status = sweep(copy, opts[:team])
      if status != 0, do: exit({:shutdown, status})
    after
      for path <- [copy, copy <> "-wal", copy <> "-shm"], do: File.rm(path)
    end
  end

  defp sweep(copy, team) do
    env = [{"MIX_ENV", "test"}, {"SWEEP_DATABASE", copy}, {"SWEEP_TEAM", team || ""}]

    {_out, status} =
      System.cmd("mix", ["test", @test_file, "--only", "sweep"],
        env: env,
        into: IO.stream(),
        stderr_to_stdout: true
      )

    status
  end

  # VACUUM INTO copies a live database consistently, WAL included, without writing to it.
  # Exqlite is the SQLite driver under ecto_sqlite3.
  # cspell:ignore Exqlite
  defp copy!(source, copy) do
    {:ok, db} = Exqlite.Sqlite3.open(source, mode: :readonly)

    try do
      :ok = Exqlite.Sqlite3.execute(db, "VACUUM INTO '#{String.replace(copy, "'", "''")}'")
    after
      Exqlite.Sqlite3.close(db)
    end
  end
end
