defmodule App.Repo.Migrations.CreateDemoTeams do
  use Ecto.Migration

  # Try a demo (#857): a visitor's name and email, kept until their copy of Coast Range
  # SAR is deleted, 7 days at most. team_id is set once the link is opened and the copy
  # is built.
  def change do
    create table(:demo_teams) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :team_id, references(:teams, on_delete: :delete_all)
      add :expires_at, :utc_datetime, null: false
      add :warned_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:demo_teams, [:email])
    create unique_index(:demo_teams, [:team_id])
  end
end
