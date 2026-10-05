defmodule App.Repo.Migrations.CreateAttendanceLinksAndScans do
  use Ecto.Migration

  # Taking attendance at the door (#139). A team admin makes a link for one activity, and
  # whoever holds it records members arriving and leaving. The token is kept encrypted so
  # the admin can copy the link again; its hash is what a visit looks up.
  def change do
    create table(:attendance_links) do
      add :team_id, references(:teams), null: false
      add :activity_id, references(:activities), null: false
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :token, :binary, null: false
      add :token_hash, :string, null: false
      add :closed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:attendance_links, [:token_hash])
    create index(:attendance_links, [:activity_id])

    # One row per scan. `kind` is "arrived" or "left"; `override_at` is the time the
    # person at the door typed, when it isn't the moment of the scan.
    create table(:attendance_scans) do
      add :team_id, references(:teams), null: false
      add :activity_id, references(:activities), null: false
      add :member_id, references(:members), null: false
      add :attendance_link_id, references(:attendance_links, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :method, :string, null: false
      add :scanned_at, :utc_datetime_usec, null: false
      add :override_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:attendance_scans, [:activity_id, :member_id])
  end
end
