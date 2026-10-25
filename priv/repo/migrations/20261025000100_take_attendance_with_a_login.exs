defmodule App.Repo.Migrations.TakeAttendanceWithALogin do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # Taking attendance needs a login (#475), so attendance links and their short links go,
  # and each scan records who took it. SQLite can't drop `attendance_link_id`, a foreign
  # key, so the table is rebuilt, as #421 rebuilt members. Nothing points at
  # attendance_scans, so foreign keys can stay on. Old scans have no recorder.
  def up do
    execute("""
    CREATE TABLE "attendance_scans_new" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "team_id" INTEGER NOT NULL CONSTRAINT "attendance_scans_team_id_fkey" REFERENCES "teams"("id"),
      "activity_id" INTEGER NOT NULL CONSTRAINT "attendance_scans_activity_id_fkey" REFERENCES "activities"("id"),
      "member_id" INTEGER NOT NULL CONSTRAINT "attendance_scans_member_id_fkey" REFERENCES "members"("id"),
      "recorded_by_user_id" INTEGER CONSTRAINT "attendance_scans_recorded_by_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
      "recorded_by_member_id" INTEGER CONSTRAINT "attendance_scans_recorded_by_member_id_fkey" REFERENCES "members"("id") ON DELETE SET NULL,
      "kind" TEXT NOT NULL,
      "method" TEXT NOT NULL,
      "scanned_at" TEXT NOT NULL,
      "override_at" TEXT,
      "inserted_at" TEXT NOT NULL,
      "updated_at" TEXT NOT NULL
    )
    """)

    copy_scans()

    drop table(:attendance_links)
    drop table(:short_links)
  end

  # The links come back empty, and the scans without their recorders.
  def down do
    create table(:short_links) do
      add :code, :string, null: false
      add :target, :binary, null: false
      add :team_id, references(:teams)
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:short_links, [:code])

    create table(:attendance_links) do
      add :team_id, references(:teams), null: false
      add :activity_id, references(:activities), null: false
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :token, :binary, null: false
      add :token_hash, :string, null: false
      add :closed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)

      add :short_link_id, references(:short_links, on_delete: :nilify_all)
    end

    create unique_index(:attendance_links, [:token_hash])
    create index(:attendance_links, [:activity_id])

    execute("""
    CREATE TABLE "attendance_scans_new" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "team_id" INTEGER NOT NULL CONSTRAINT "attendance_scans_team_id_fkey" REFERENCES "teams"("id"),
      "activity_id" INTEGER NOT NULL CONSTRAINT "attendance_scans_activity_id_fkey" REFERENCES "activities"("id"),
      "member_id" INTEGER NOT NULL CONSTRAINT "attendance_scans_member_id_fkey" REFERENCES "members"("id"),
      "attendance_link_id" INTEGER CONSTRAINT "attendance_scans_attendance_link_id_fkey" REFERENCES "attendance_links"("id") ON DELETE SET NULL,
      "kind" TEXT NOT NULL,
      "method" TEXT NOT NULL,
      "scanned_at" TEXT NOT NULL,
      "override_at" TEXT,
      "inserted_at" TEXT NOT NULL,
      "updated_at" TEXT NOT NULL
    )
    """)

    copy_scans()
  end

  defp copy_scans do
    columns =
      "id, team_id, activity_id, member_id, kind, method, scanned_at, override_at, " <>
        "inserted_at, updated_at"

    execute(
      "INSERT INTO attendance_scans_new (#{columns}) SELECT #{columns} FROM attendance_scans"
    )

    execute("DROP TABLE attendance_scans")
    execute("ALTER TABLE attendance_scans_new RENAME TO attendance_scans")
    create index(:attendance_scans, [:activity_id, :member_id])
  end
end
