defmodule App.Repo.Migrations.AiAsksForOrganizations do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # An organization's admins write its forms with AI writing too (#1089), and its asks
  # count toward its own daily limit. So an ask belongs to a team or an organization,
  # exactly one. SQLite can't drop NOT NULL, so ai_asks is rebuilt; nothing points at it.

  @columns "id, team_id, user_id, kind, ask, model, input_tokens, cache_write_tokens, " <>
             "cache_read_tokens, output_tokens, cost_microdollars, turns, duration_ms, " <>
             "outcome, asked_at"

  def up do
    execute("""
    CREATE TABLE "ai_asks_new" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "team_id" INTEGER CONSTRAINT "ai_asks_team_id_fkey" REFERENCES "teams"("id") ON DELETE CASCADE,
      "organization_id" INTEGER CONSTRAINT "ai_asks_organization_id_fkey" REFERENCES "organizations"("id") ON DELETE CASCADE,
      "user_id" INTEGER CONSTRAINT "ai_asks_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
      "kind" TEXT NOT NULL,
      "ask" TEXT,
      "model" TEXT NOT NULL,
      "input_tokens" INTEGER DEFAULT 0 NOT NULL,
      "cache_write_tokens" INTEGER DEFAULT 0 NOT NULL,
      "cache_read_tokens" INTEGER DEFAULT 0 NOT NULL,
      "output_tokens" INTEGER DEFAULT 0 NOT NULL,
      "cost_microdollars" INTEGER DEFAULT 0 NOT NULL,
      "turns" INTEGER DEFAULT 0 NOT NULL,
      "duration_ms" INTEGER,
      "outcome" TEXT NOT NULL,
      "asked_at" TEXT NOT NULL,
      CONSTRAINT "ai_asks_one_owner" CHECK (("team_id" IS NULL) <> ("organization_id" IS NULL))
    )
    """)

    execute("INSERT INTO ai_asks_new (#{@columns}) SELECT #{@columns} FROM ai_asks")
    execute("DROP TABLE ai_asks")
    execute("ALTER TABLE ai_asks_new RENAME TO ai_asks")
    indexes()
    create index(:ai_asks, [:organization_id, :asked_at])
  end

  # Drops every organization's ask, since the old table has no place for one.
  def down do
    execute("""
    CREATE TABLE "ai_asks_new" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "team_id" INTEGER NOT NULL CONSTRAINT "ai_asks_team_id_fkey" REFERENCES "teams"("id") ON DELETE CASCADE,
      "user_id" INTEGER CONSTRAINT "ai_asks_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
      "kind" TEXT NOT NULL,
      "ask" TEXT,
      "model" TEXT NOT NULL,
      "input_tokens" INTEGER DEFAULT 0 NOT NULL,
      "cache_write_tokens" INTEGER DEFAULT 0 NOT NULL,
      "cache_read_tokens" INTEGER DEFAULT 0 NOT NULL,
      "output_tokens" INTEGER DEFAULT 0 NOT NULL,
      "cost_microdollars" INTEGER DEFAULT 0 NOT NULL,
      "turns" INTEGER DEFAULT 0 NOT NULL,
      "duration_ms" INTEGER,
      "outcome" TEXT NOT NULL,
      "asked_at" TEXT NOT NULL
    )
    """)

    execute(
      "INSERT INTO ai_asks_new (#{@columns}) SELECT #{@columns} FROM ai_asks WHERE team_id IS NOT NULL"
    )

    execute("DROP TABLE ai_asks")
    execute("ALTER TABLE ai_asks_new RENAME TO ai_asks")
    indexes()
  end

  defp indexes do
    create index(:ai_asks, [:asked_at])
    create index(:ai_asks, [:team_id, :asked_at])
    create index(:ai_asks, [:user_id])
  end
end
