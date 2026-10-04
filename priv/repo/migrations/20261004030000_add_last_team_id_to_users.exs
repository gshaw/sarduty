defmodule App.Repo.Migrations.AddLastTeamIdToUsers do
  use Ecto.Migration

  # The team a user last opened, so logging in lands on it when they manage several.
  def change do
    alter table(:users) do
      add :last_team_id, references(:teams, on_delete: :nilify_all)
    end
  end
end
