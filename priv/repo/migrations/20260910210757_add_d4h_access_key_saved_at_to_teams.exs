defmodule App.Repo.Migrations.AddD4hAccessKeySavedAtToTeams do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :d4h_access_key_saved_at, :utc_datetime_usec
    end
  end
end
