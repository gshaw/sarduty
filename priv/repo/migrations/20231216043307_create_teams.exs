defmodule App.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams) do
      add :name, :string, null: false
      add :subdomain, :string, null: false
      add :d4h_team_id, :integer, null: false
      add :d4h_api_host, :string, null: false
      add :mailing_address, :string
      add :lat, :float, null: false, default: 0.0
      add :lng, :float, null: false, default: 0.0
      add :timezone, :string, null: false, default: "America/Vancouver"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:teams, [:d4h_team_id])

    alter table(:users) do
      # Force users to add their access key again so a team is created and associated
      remove :d4h_access_key, :binary
      remove :d4h_team_title, :string
      remove :d4h_team_subdomain, :string
      remove :d4h_api_host, :string
      remove :d4h_changed_at, :utc_datetime

      add :team_id, references(:teams)
      add :d4h_access_key, :string
    end
  end
end
