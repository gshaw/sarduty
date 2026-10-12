defmodule App.Repo.Migrations.CreateTagsAndKitTags do
  use Ecto.Migration

  # Kit tags (#162): a copy of the team's D4H tags, kept by the sync, and the tags a kit
  # adds to an activity. A tag D4H deletes leaves its kits.
  def change do
    create table(:tags) do
      add :team_id, references(:teams), null: false
      add :d4h_tag_id, :integer, null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tags, [:team_id, :d4h_tag_id])

    create table(:kit_tags) do
      add :kit_id, references(:kits, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:kit_tags, [:kit_id, :tag_id])
    create index(:kit_tags, [:tag_id])
  end
end
