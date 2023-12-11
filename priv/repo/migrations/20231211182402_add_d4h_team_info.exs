defmodule App.Repo.Migrations.AddD4HTeamInfo do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :d4h_team_title, :string
      add :d4h_team_subdomain, :string
    end
  end
end
