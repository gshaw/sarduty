defmodule App.Repo.Migrations.AddDeletedAtToActivities do
  use Ecto.Migration

  # D4H leaves deleted activities out of its lists. The refresh marks them here rather
  # than deleting them, since attendance links, scans, and no-shows point at them (#160).
  def change do
    alter table(:activities) do
      add :deleted_at, :utc_datetime
    end
  end
end
