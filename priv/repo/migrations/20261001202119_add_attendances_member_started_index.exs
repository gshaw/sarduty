defmodule App.Repo.Migrations.AddAttendancesMemberStartedIndex do
  use Ecto.Migration

  # Hours per member for a year: the members page, tax credit letters, and a
  # member's attendance list all filter on these three.
  def change do
    create index(:attendances, [:member_id, :status, :started_at])
  end
end
