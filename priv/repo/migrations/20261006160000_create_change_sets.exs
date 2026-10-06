defmodule App.Repo.Migrations.CreateChangeSets do
  use Ecto.Migration

  # Every write SAR Duty makes to D4H is a change set (#174): what proposed it, one row
  # per D4H record with what D4H had and what it gets, and D4H's answer for each row.
  def change do
    create table(:change_sets) do
      add :team_id, references(:teams), null: false
      add :source, :string, null: false
      add :activity_id, references(:activities)
      add :group_id, references(:groups, on_delete: :nilify_all)
      add :proposed_by_user_id, references(:users, on_delete: :nilify_all)
      add :applied_by_user_id, references(:users, on_delete: :nilify_all)
      add :applied_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:change_sets, [:team_id, :inserted_at])

    create table(:change_set_rows) do
      add :change_set_id, references(:change_sets, on_delete: :delete_all), null: false
      add :team_id, references(:teams), null: false
      add :member_id, references(:members)
      add :action, :string, null: false
      add :d4h_record_id, :integer
      add :old_value, :map
      add :new_value, :map, null: false
      add :reason, :string
      add :status, :string, null: false
      add :error, :string
      add :applied_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:change_set_rows, [:change_set_id])
    create index(:change_set_rows, [:team_id, :member_id])
  end
end
