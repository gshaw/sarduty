defmodule App.SampleRepo do
  @moduledoc """
  Coast Range SAR's own database (#816): the made-up team an agent's report runs on
  (`App.Report.run_sample/3`), never a real team's rows. Same migrations as App.Repo,
  in a SQLite file of its own beside it, rebuilt from `App.CoastRange` at boot and
  again every night (App.Worker.ReseedSampleWorker), so "last 30 days" always has rows.

  A file rather than `:memory:`: a report that runs past 2 seconds disconnects its
  connection (App.Report.Runner), and an in-memory database closes with it. See
  docs/reports.md, Coast Range SAR.
  """

  use Ecto.Repo,
    otp_app: :sarduty,
    adapter: Ecto.Adapters.SQLite3

  import Ecto.Query, only: [from: 2]

  alias App.CoastRange
  alias App.Model.Team
  alias App.Operation.SeedCoastRange

  require Logger

  @doc """
  Before the supervisor, as App.Release.migrate/0 is: migrates the file and seeds it, on
  one connection so no migration is prepared against a stale schema. A failure is
  logged, never raised: the site runs without Coast Range SAR, and run_sample/3 says so.
  """
  def prepare(now \\ DateTime.utc_now()) do
    {:ok, {:ok, _rows}, _} = Ecto.Migrator.with_repo(__MODULE__, &prepare(&1, now), pool_size: 1)
    :ok
  rescue
    error ->
      Logger.error("Coast Range SAR was not seeded: " <> Exception.message(error))
      :error
  end

  # App.Release.migrate/0 may have just compiled the same migrations, and compiling one
  # again warns that its module is redefined.
  defp prepare(repo, now) do
    conflicts? = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      path = Ecto.Migrator.migrations_path(App.Repo)
      Ecto.Migrator.run(repo, path, :up, all: true, log: false)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts?)
    end

    reseed!(now)
  end

  @doc """
  Empties every table and seeds Coast Range SAR as of `now`, in one transaction, so a
  report that runs meanwhile reads the old rows or the new, never none. Ids start from 1
  each time.
  """
  def reseed!(now \\ DateTime.utc_now()) do
    transaction(fn ->
      query!("PRAGMA defer_foreign_keys = ON")
      Enum.each(tables(), &query!(~s(DELETE FROM "#{&1}")))
      query!("DELETE FROM sqlite_sequence")
      rows = SeedCoastRange.call(__MODULE__, now)
      organization = insert!(CoastRange.organization())

      rows
      |> Map.fetch!({:team, :coastrange})
      |> Ecto.Changeset.change(organization_id: organization.id)
      |> update!()
    end)
  end

  # Every table the migrations made, but their own record of what ran.
  defp tables do
    %{rows: rows} =
      query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'schema_migrations'"
      )

    List.flatten(rows)
  end

  @doc "Coast Range SAR's team, or nil before it is seeded."
  def team, do: one(from(t in Team, where: t.subdomain == "coastrange"))
end
