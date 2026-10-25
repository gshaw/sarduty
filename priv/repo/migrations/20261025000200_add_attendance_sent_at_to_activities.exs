defmodule App.Repo.Migrations.AddAttendanceSentAtToActivities do
  use Ecto.Migration

  # Needs attention lists an activity's scans until a team admin's review is done: its
  # send went through, or it had nothing to send (#475). Usec, as scans' inserted_at, so
  # the two compare as text. Activities sent before start from their latest send whose
  # rows all went through, so they don't come back on the day this runs; one whose send
  # failed shows, as it should have.
  def up do
    alter table(:activities) do
      add :attendance_sent_at, :utc_datetime_usec
    end

    execute("""
    UPDATE activities SET attendance_sent_at = (
      SELECT max(change_sets.inserted_at) FROM change_sets
      WHERE change_sets.activity_id = activities.id
        AND change_sets.team_id = activities.team_id
        AND change_sets.source = 'door'
        AND NOT EXISTS (
          SELECT 1 FROM change_set_rows
          WHERE change_set_rows.change_set_id = change_sets.id
            AND change_set_rows.status != 'applied'
        )
    )
    WHERE id IN (SELECT activity_id FROM change_sets WHERE source = 'door')
    """)
  end

  def down do
    alter table(:activities) do
      remove :attendance_sent_at
    end
  end
end
