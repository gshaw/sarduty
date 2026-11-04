defmodule App.Repo.Migrations.CreateDemoTeams do
  use Ecto.Migration

  # Try a demo (#857): a link opens it, and no email is asked. Nothing in production had
  # the email version's table, so it was replaced rather than altered; a dev database
  # that ran it has it dropped first. team_id is set once the copy is built. A visitor's
  # name, if they gave one, is their member's on the demo team, kept until it's deleted.
  def up do
    drop_if_exists table(:demo_teams)

    create table(:demo_teams) do
      add :kind, :string, null: false
      add :name, :string
      add :user_id, references(:users, on_delete: :nilify_all)
      add :team_id, references(:teams, on_delete: :delete_all)
      add :expires_at, :utc_datetime, null: false
      add :seen_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:demo_teams, [:team_id])
    create index(:demo_teams, [:user_id])
  end

  def down, do: drop(table(:demo_teams))
end
