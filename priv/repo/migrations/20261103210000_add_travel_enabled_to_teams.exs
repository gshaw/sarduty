defmodule App.Repo.Migrations.AddTravelEnabledToTeams do
  use Ecto.Migration

  # Travel (#230) is a feature teams turn on. Teams that set some already keep it.
  def up do
    alter table(:teams) do
      add :travel_enabled, :boolean, null: false, default: false
    end

    flush()

    execute "UPDATE teams SET travel_enabled = 1 WHERE id IN (SELECT DISTINCT team_id FROM trips)"
  end

  def down do
    alter table(:teams) do
      remove :travel_enabled
    end
  end
end
