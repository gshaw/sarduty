defmodule App.Repo.Migrations.AddAttendanceRepliedAt do
  use Ecto.Migration

  # When the member replied to the invitation (#444): in SAR Duty, or when the refresh
  # saw the status change in D4H. Nil on rows from before, and on rows with no reply.
  def change do
    alter table(:attendances) do
      add :replied_at, :utc_datetime
    end
  end
end
