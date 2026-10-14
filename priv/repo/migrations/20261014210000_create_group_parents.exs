defmodule App.Repo.Migrations.CreateGroupParents do
  use Ecto.Migration

  # A group can start from another group: its rule is the parent's endorsements plus its
  # own (#327). Both groups are by D4H id, like group_endorsements.
  def change do
    create table(:group_parents) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_group_id, :integer, null: false
      add :parent_d4h_group_id, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_parents, [:team_id, :d4h_group_id])
  end
end
