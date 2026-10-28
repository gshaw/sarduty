defmodule App.Repo.Migrations.RemoveAgentChoreProposals do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # AI agents proposed chores through the MCP until it became read-only (#627). Their
  # change sets go, as does the chore's link to its proposal: nothing makes either now,
  # and a member's history crashed on one. The chores stay. SQLite can't drop
  # `change_set_row_id`, a foreign key, so chores is rebuilt, as #475 rebuilt
  # attendance_scans. Nothing points at chores.
  def up do
    execute("""
    CREATE TABLE "chores_new" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "team_id" INTEGER NOT NULL CONSTRAINT "chores_team_id_fkey" REFERENCES "teams"("id"),
      "member_id" INTEGER NOT NULL CONSTRAINT "chores_member_id_fkey" REFERENCES "members"("id"),
      "chore_category_id" INTEGER NOT NULL CONSTRAINT "chores_chore_category_id_fkey" REFERENCES "chore_categories"("id"),
      "date" TEXT NOT NULL,
      "minutes" INTEGER NOT NULL,
      "description" TEXT NOT NULL,
      "status" TEXT DEFAULT 'waiting' NOT NULL,
      "decided_by_user_id" INTEGER CONSTRAINT "chores_decided_by_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
      "decided_at" TEXT,
      "decline_reason" TEXT,
      "inserted_at" TEXT NOT NULL,
      "updated_at" TEXT NOT NULL,
      "chore_event_id" INTEGER CONSTRAINT "chores_chore_event_id_fkey" REFERENCES "chore_events"("id") ON DELETE SET NULL
    )
    """)

    columns =
      "id, team_id, member_id, chore_category_id, date, minutes, description, status, " <>
        "decided_by_user_id, decided_at, decline_reason, inserted_at, updated_at, chore_event_id"

    execute("INSERT INTO chores_new (#{columns}) SELECT #{columns} FROM chores")
    execute("DROP TABLE chores")
    execute("ALTER TABLE chores_new RENAME TO chores")
    create index(:chores, [:team_id, :status])
    create index(:chores, [:member_id, :date])
    create index(:chores, [:chore_category_id])
    create index(:chores, [:chore_event_id])

    execute("""
    DELETE FROM change_sets WHERE id IN
      (SELECT change_set_id FROM change_set_rows WHERE action = 'add_chore')
    """)

    execute("DELETE FROM change_set_rows WHERE action = 'add_chore'")
  end

  # The proposals don't come back; the chores get the column back, empty.
  def down do
    alter table(:chores) do
      add :change_set_row_id, references(:change_set_rows, on_delete: :nilify_all)
    end
  end
end
