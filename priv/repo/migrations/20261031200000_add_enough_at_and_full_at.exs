defmodule App.Repo.Migrations.AddEnoughAtAndFullAt do
  use Ecto.Migration

  # How many members an activity needs and has room for (#447). SAR Duty's own, never
  # D4H's, so a refresh leaves them alone. A template holds them as details (#746).
  def change do
    alter table(:activities) do
      add :enough_at, :integer
      add :full_at, :integer
    end

    alter table(:templates) do
      add :enough_at, :integer
      add :full_at, :integer
    end
  end
end
