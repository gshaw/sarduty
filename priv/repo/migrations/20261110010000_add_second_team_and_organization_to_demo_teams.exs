defmodule App.Repo.Migrations.AddSecondTeamAndOrganizationToDemoTeams do
  use Ecto.Migration

  # A demo is an organization now (#963): Coast Range SAR (team_id), Silver Basin SAR
  # (second_team_id), and WESARA's copy of its own (organization_id). Deleting either
  # leaves the row; App.Operation.DeleteDemo deletes all three.
  def up do
    alter table(:demo_teams) do
      add :second_team_id, references(:teams, on_delete: :nilify_all)
      add :organization_id, references(:organizations, on_delete: :nilify_all)
    end

    create unique_index(:demo_teams, [:second_team_id])
  end

  # SQLite drops no column a foreign key is on, so down rebuilds the table without them,
  # as ecto_sqlite3 made it. cspell:ignore fkey
  def down do
    drop index(:demo_teams, [:second_team_id])

    execute """
    CREATE TABLE demo_teams_down (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      name TEXT,
      user_id INTEGER CONSTRAINT demo_teams_user_id_fkey REFERENCES users(id) ON DELETE SET NULL,
      team_id INTEGER CONSTRAINT demo_teams_team_id_fkey REFERENCES teams(id) ON DELETE CASCADE,
      expires_at TEXT NOT NULL,
      seen_at TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      outbox_seen_at TEXT
    )
    """

    execute """
    INSERT INTO demo_teams_down
    SELECT id, kind, name, user_id, team_id, expires_at, seen_at, inserted_at, updated_at,
           outbox_seen_at
    FROM demo_teams
    """

    execute "DROP TABLE demo_teams"
    execute "ALTER TABLE demo_teams_down RENAME TO demo_teams"
    create unique_index(:demo_teams, [:team_id])
    create index(:demo_teams, [:user_id])
  end
end
