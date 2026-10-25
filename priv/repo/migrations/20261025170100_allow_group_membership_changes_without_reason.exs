defmodule App.Repo.Migrations.AllowGroupMembershipChangesWithoutReason do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # A team admin's add or remove by hand has no reason (#546). SQLite can't drop NOT NULL,
  # so the table is rebuilt. Nothing points at it, so foreign keys can stay on.
  def up, do: Enum.each(statements(~s|"reason" TEXT|), &execute/1)

  # Fails if a change has no reason: give each one first.
  def down, do: Enum.each(statements(~s|"reason" TEXT NOT NULL|), &execute/1)

  defp statements(reason) do
    columns = "id, team_id, d4h_group_id, member_id, user_id, action, reason, error, inserted_at"

    [
      """
      CREATE TABLE "group_membership_changes_new" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "team_id" INTEGER NOT NULL CONSTRAINT "group_membership_changes_team_id_fkey" REFERENCES "teams"("id"),
        "d4h_group_id" INTEGER NOT NULL,
        "member_id" INTEGER NOT NULL CONSTRAINT "group_membership_changes_member_id_fkey" REFERENCES "members"("id"),
        "user_id" INTEGER CONSTRAINT "group_membership_changes_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
        "action" TEXT NOT NULL,
        #{reason},
        "error" TEXT,
        "inserted_at" TEXT NOT NULL
      )
      """,
      "INSERT INTO group_membership_changes_new (#{columns}) SELECT #{columns} FROM group_membership_changes",
      "DROP TABLE group_membership_changes",
      "ALTER TABLE group_membership_changes_new RENAME TO group_membership_changes",
      ~s|CREATE INDEX "group_membership_changes_team_id_d4h_group_id_inserted_at_index" ON "group_membership_changes" ("team_id", "d4h_group_id", "inserted_at")|
    ]
  end
end
