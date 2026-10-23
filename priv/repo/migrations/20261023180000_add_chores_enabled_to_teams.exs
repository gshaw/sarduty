defmodule App.Repo.Migrations.AddChoresEnabledToTeams do
  use Ecto.Migration

  # Chores (#341) hide behind a team setting while they change. Every team starts off.
  def change do
    alter table(:teams) do
      add :chores_enabled, :boolean, null: false, default: false
    end
  end
end
