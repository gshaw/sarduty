defmodule App.Repo.Migrations.CreateChoreCategories do
  use Ecto.Migration

  # Chore categories (#341): what a member picks when they log a chore. Each is its own
  # D4H event per month, with an hours tag and other tags. Archived, never deleted, so old
  # chores keep theirs.
  def change do
    create table(:chore_categories) do
      add :team_id, references(:teams), null: false
      add :title, :string, null: false
      add :hours, :string, null: false
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chore_categories, [:team_id])

    create table(:chore_category_tags) do
      add :chore_category_id, references(:chore_categories, on_delete: :delete_all), null: false

      add :tag_id, references(:tags, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:chore_category_tags, [:chore_category_id, :tag_id])
    create index(:chore_category_tags, [:tag_id])
  end
end
