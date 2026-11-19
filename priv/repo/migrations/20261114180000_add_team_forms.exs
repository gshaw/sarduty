defmodule App.Repo.Migrations.AddTeamForms do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # A form belongs to a team or an organization (#1083), so `forms` gains `team_id` and
  # `organization_id` may be empty, with exactly one of them set. Teams gain
  # `forms_enabled`, the switch SAR Duty turns on per team.
  #
  # SQLite can't drop NOT NULL, so `forms` is rebuilt. Three tables point at forms:
  # form_pages and sign_requests ON DELETE CASCADE, published_pdfs SET NULL, so dropping
  # it with foreign keys on would delete or unlink their rows. They go off first. That
  # pragma does nothing inside a transaction, so this migration runs outside Ecto's, on
  # one connection, and copies inside its own.
  @disable_ddl_transaction true

  @columns "id, organization_id, name, about, text, page_sha256, version, user_id, " <>
             "inserted_at, updated_at, state"

  def up do
    rebuild([
      """
      CREATE TABLE "forms_new" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "organization_id" INTEGER CONSTRAINT "forms_organization_id_fkey" REFERENCES "organizations"("id") ON DELETE CASCADE,
        "team_id" INTEGER CONSTRAINT "forms_team_id_fkey" REFERENCES "teams"("id") ON DELETE CASCADE,
        "name" TEXT NOT NULL,
        "about" TEXT,
        "text" TEXT NOT NULL,
        "page_sha256" TEXT,
        "version" INTEGER DEFAULT 1 NOT NULL,
        "user_id" INTEGER CONSTRAINT "forms_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
        "inserted_at" TEXT NOT NULL,
        "updated_at" TEXT NOT NULL,
        "state" TEXT DEFAULT 'off' NOT NULL,
        CONSTRAINT "forms_one_owner" CHECK (("organization_id" IS NULL) <> ("team_id" IS NULL))
      )
      """,
      "INSERT INTO forms_new (#{@columns}) SELECT #{@columns} FROM forms",
      "DROP TABLE forms",
      "ALTER TABLE forms_new RENAME TO forms",
      ~s|CREATE UNIQUE INDEX "forms_organization_id_name_index" ON "forms" ("organization_id", "name")|,
      ~s|CREATE UNIQUE INDEX "forms_team_id_name_index" ON "forms" ("team_id", "name")|,
      ~s|ALTER TABLE "teams" ADD COLUMN "forms_enabled" INTEGER DEFAULT false NOT NULL|
    ])
  end

  # Deletes every team's form first, with what hangs off it, since the old table has no
  # place for one.
  def down do
    rebuild([
      "DELETE FROM form_pages WHERE form_id IN (SELECT id FROM forms WHERE team_id IS NOT NULL)",
      "DELETE FROM sign_requests WHERE form_id IN (SELECT id FROM forms WHERE team_id IS NOT NULL)",
      "UPDATE published_pdfs SET form_id = NULL WHERE form_id IN (SELECT id FROM forms WHERE team_id IS NOT NULL)",
      "DELETE FROM forms WHERE team_id IS NOT NULL",
      """
      CREATE TABLE "forms_new" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "organization_id" INTEGER NOT NULL CONSTRAINT "forms_organization_id_fkey" REFERENCES "organizations"("id") ON DELETE CASCADE,
        "name" TEXT NOT NULL,
        "about" TEXT,
        "text" TEXT NOT NULL,
        "page_sha256" TEXT,
        "version" INTEGER DEFAULT 1 NOT NULL,
        "user_id" INTEGER CONSTRAINT "forms_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
        "inserted_at" TEXT NOT NULL,
        "updated_at" TEXT NOT NULL,
        "state" TEXT DEFAULT 'off' NOT NULL
      )
      """,
      "INSERT INTO forms_new (#{@columns}) SELECT #{@columns} FROM forms",
      "DROP TABLE forms",
      "ALTER TABLE forms_new RENAME TO forms",
      ~s|CREATE UNIQUE INDEX "forms_organization_id_name_index" ON "forms" ("organization_id", "name")|,
      ~s|ALTER TABLE "teams" DROP COLUMN "forms_enabled"|
    ])
  end

  defp rebuild(statements) do
    repo = repo()

    repo.checkout(fn ->
      repo.query!("PRAGMA foreign_keys = OFF")

      try do
        repo.transaction(fn -> Enum.each(statements, &repo.query!/1) end)
      after
        repo.query!("PRAGMA foreign_keys = ON")
      end
    end)
  end
end
