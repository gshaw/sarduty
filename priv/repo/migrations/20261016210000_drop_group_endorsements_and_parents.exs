defmodule App.Repo.Migrations.DropGroupEndorsementsAndParents do
  use Ecto.Migration

  # Group rules replaced these in #334, and they were kept one release.
  def up do
    drop table(:group_endorsements)
    drop table(:group_parents)
  end

  def down do
    create table(:group_endorsements) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_group_id, :integer, null: false
      add :endorsement_id, references(:endorsements, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_endorsements, [:team_id, :d4h_group_id, :endorsement_id])
    create index(:group_endorsements, [:endorsement_id])

    create table(:group_parents) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_group_id, :integer, null: false
      add :parent_d4h_group_id, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_parents, [:team_id, :d4h_group_id])
  end
end
