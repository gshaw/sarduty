defmodule App.Repo.Migrations.CreateGroupMembershipChanges do
  use Ecto.Migration

  def change do
    # Keyed by d4h_group_id, like the rules, so the log outlives a group the sync
    # deletes.
    create table(:group_membership_changes) do
      add :team_id, references(:teams), null: false
      add :d4h_group_id, :integer, null: false
      add :member_id, references(:members), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :reason, :string, null: false
      add :error, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:group_membership_changes, [:team_id, :d4h_group_id, :inserted_at])
  end
end
