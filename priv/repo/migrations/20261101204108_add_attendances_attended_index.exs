defmodule App.Repo.Migrations.AddAttendancesAttendedIndex do
  use Ecto.Migration

  # Attendance.attended/2 by activity, read from the index alone: each member's last
  # activity, and their activities and hours in a period, for Members and Home (#784).
  def change do
    create index(:attendances, [
             :activity_id,
             :status,
             :started_at,
             :member_id,
             :duration_in_minutes
           ])
  end
end
