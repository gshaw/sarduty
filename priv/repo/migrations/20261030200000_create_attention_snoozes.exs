defmodule App.Repo.Migrations.CreateAttentionSnoozes do
  use Ecto.Migration

  # A team admin's snooze of a Needs attention item (#751), one per team and item. `ids`
  # are the local ids behind the item when it was snoozed (members, activities, or awards,
  # by key): anything new brings the item back early.
  def change do
    create table(:attention_snoozes) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :ids, {:array, :integer}, null: false
      add :until, :utc_datetime, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:attention_snoozes, [:team_id, :key])
    create index(:attention_snoozes, [:user_id])
  end
end
