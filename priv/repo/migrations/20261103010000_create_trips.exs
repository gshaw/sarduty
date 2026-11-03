defmodule App.Repo.Migrations.CreateTrips do
  use Ecto.Migration

  # How each attended row got to an activity, and the km it counts (#230). One per
  # attendance row, keyed by D4H's attendance id so a row the refresh deletes and copies
  # back keeps its trip. SAR Duty's own data: the km reach D4H only by hand.
  def change do
    create table(:trips) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :d4h_attendance_id, :integer, null: false
      add :travel, :string, null: false
      add :km, :integer, null: false
      add :set_by_user_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:trips, [:activity_id, :d4h_attendance_id])
    create index(:trips, [:team_id])
    create index(:trips, [:member_id])
    create index(:trips, [:set_by_user_id])
  end
end
