defmodule App.Ops.Backup do
  @moduledoc """
  Writes a consistent copy of the database to /tmp/backup.db with VACUUM INTO, for
  `bin/prod backup`, which then tars it with the team logos over `fly ssh`, encrypts it
  to the backup age key, and removes it. Tarring the live file could catch the WAL
  mid-write, and the image has no sqlite3.
  """

  use App.Ops.Task,
    name: "backup",
    usage: "backup",
    summary: "An encrypted copy of the database and logos, in backups/."

  alias App.Repo

  # bin/prod tars this path; the two must agree.
  @snapshot "/tmp/backup.db"

  @impl App.Ops.Task
  def run([]) do
    File.rm(@snapshot)
    # Longer than the Repo's 15 s limit: it took over a minute on 2026-11-07.
    Repo.query!("VACUUM INTO ?1", [@snapshot], timeout: 300_000)
    {:ok, "Wrote #{@snapshot}, #{Service.Format.file_size(File.stat!(@snapshot).size)}."}
  end

  def run(_args), do: {:error, "Usage: " <> usage()}
end
