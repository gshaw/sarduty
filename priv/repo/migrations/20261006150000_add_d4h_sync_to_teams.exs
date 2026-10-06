defmodule App.Repo.Migrations.AddD4hSyncToTeams do
  use Ecto.Migration

  # The sync every 10 minutes (#163): when it last ran, and what each D4H list looked
  # like then, so the next one can tell what changed.
  def change do
    alter table(:teams) do
      add :d4h_synced_at, :utc_datetime_usec
      add :d4h_sync_state, :map
    end
  end
end
