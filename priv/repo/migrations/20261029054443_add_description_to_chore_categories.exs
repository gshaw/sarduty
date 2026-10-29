defmodule App.Repo.Migrations.AddDescriptionToChoreCategories do
  use Ecto.Migration

  # A line under the category's name on Log a chore, saying what it covers. Nil until a
  # team admin writes one.
  def change do
    alter table(:chore_categories) do
      add :description, :string
    end
  end
end
