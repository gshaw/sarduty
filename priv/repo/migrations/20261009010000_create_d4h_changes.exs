defmodule App.Repo.Migrations.CreateD4HChanges do
  use Ecto.Migration

  # What the D4H sync saw change, kept as each member's and activity's history (#174,
  # step 3). Qualifications and groups can be deleted by the sync, so their rows keep a
  # `label` and the reference goes to null.
  def change do
    create table(:d4h_changes) do
      add :team_id, references(:teams), null: false
      add :member_id, references(:members)
      add :activity_id, references(:activities)
      add :qualification_id, references(:qualifications, on_delete: :nilify_all)
      add :group_id, references(:groups, on_delete: :nilify_all)
      add :record_kind, :string, null: false
      add :action, :string, null: false
      add :d4h_record_id, :integer
      add :label, :string
      add :fields, {:array, :string}, null: false, default: []
      add :old_value, :map
      add :new_value, :map
      add :seen_after, :utc_datetime_usec
      add :seen_at, :utc_datetime_usec, null: false
    end

    create index(:d4h_changes, [:team_id, :member_id, :seen_at])
    create index(:d4h_changes, [:team_id, :activity_id, :seen_at])
    create index(:d4h_changes, [:seen_at])
  end
end
