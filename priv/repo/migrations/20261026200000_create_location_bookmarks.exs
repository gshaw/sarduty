defmodule App.Repo.Migrations.CreateLocationBookmarks do
  use Ecto.Migration

  # A copy of the team's own D4H location bookmarks (#614), which name the places in the
  # activity form. The sync replaces it; nothing else points at a row.
  def change do
    create table(:location_bookmarks) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_location_bookmark_id, :integer, null: false
      add :title, :string, null: false
      add :address, :string
      add :coordinate, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:location_bookmarks, [:team_id, :d4h_location_bookmark_id])
  end
end
