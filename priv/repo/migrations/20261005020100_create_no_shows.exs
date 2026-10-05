defmodule App.Repo.Migrations.CreateNoShows do
  use Ecto.Migration

  # Members who signed up for an activity and did not arrive, recorded when the door's
  # attendance is sent to D4H (#139), so a team admin can check on each one.
  def change do
    create table(:no_shows) do
      add :team_id, references(:teams), null: false
      add :activity_id, references(:activities), null: false
      add :member_id, references(:members), null: false
      add :followed_up_at, :utc_datetime_usec
      add :followed_up_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:no_shows, [:activity_id, :member_id])
  end
end
