defmodule App.Repo.Migrations.CreateKitGroups do
  use Ecto.Migration

  # The groups a kit invites to an activity (#162). A group D4H deletes leaves its kits.
  def change do
    create table(:kit_groups) do
      add :kit_id, references(:kits, on_delete: :delete_all), null: false
      add :group_id, references(:groups, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:kit_groups, [:kit_id, :group_id])
    create index(:kit_groups, [:group_id])
  end
end
