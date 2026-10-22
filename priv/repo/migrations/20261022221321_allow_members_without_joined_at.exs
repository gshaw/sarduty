defmodule App.Repo.Migrations.AllowMembersWithoutJoinedAt do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # D4H allows a member with no start date, so `joined_at` can be empty (#421). SQLite
  # can't drop NOT NULL, so the table is rebuilt. Fourteen tables point at members, some
  # ON DELETE CASCADE, so dropping it with foreign keys on would delete their rows. They
  # go off first. That pragma does nothing inside a transaction, so this migration runs outside
  # Ecto's, on one connection, and copies inside its own.
  @disable_ddl_transaction true

  def up, do: rebuild(~s|"joined_at" TEXT|)

  # Fails if a member has no joined date: give them one first.
  def down, do: rebuild(~s|"joined_at" TEXT NOT NULL|)

  defp rebuild(joined_at) do
    repo = repo()

    repo.checkout(fn ->
      repo.query!("PRAGMA foreign_keys = OFF")

      try do
        repo.transaction(fn -> Enum.each(statements(joined_at), &repo.query!/1) end)
      after
        repo.query!("PRAGMA foreign_keys = ON")
      end
    end)
  end

  defp statements(joined_at) do
    columns =
      "id, team_id, d4h_member_id, ref_id, name, email, phone, address, position, " <>
        "joined_at, left_at, inserted_at, updated_at, d4h_permission, d4h_status, not_a_person"

    [
      """
      CREATE TABLE "members_new" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "team_id" INTEGER NOT NULL CONSTRAINT "members_team_id_fkey" REFERENCES "teams"("id"),
        "d4h_member_id" INTEGER NOT NULL,
        "ref_id" TEXT,
        "name" TEXT NOT NULL,
        "email" TEXT,
        "phone" TEXT,
        "address" TEXT,
        "position" TEXT,
        #{joined_at},
        "left_at" TEXT,
        "inserted_at" TEXT NOT NULL,
        "updated_at" TEXT NOT NULL,
        "d4h_permission" INTEGER,
        "d4h_status" TEXT,
        "not_a_person" INTEGER DEFAULT false NOT NULL
      )
      """,
      "INSERT INTO members_new (#{columns}) SELECT #{columns} FROM members",
      "DROP TABLE members",
      "ALTER TABLE members_new RENAME TO members",
      ~s|CREATE UNIQUE INDEX "members_team_id_d4h_member_id_index" ON "members" ("team_id", "d4h_member_id")|
    ]
  end
end
