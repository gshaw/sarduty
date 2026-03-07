defmodule App.Repo.Migrations.CreateGroupsAndGroupMembers do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :team_id, references(:teams), null: false
      add :d4h_group_id, :integer, null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:groups, [:team_id, :d4h_group_id])

    create table(:group_members) do
      add :group_id, references(:groups), null: false
      add :member_id, references(:members), null: false
      add :d4h_group_membership_id, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_members, [:group_id, :member_id])
  end
end
