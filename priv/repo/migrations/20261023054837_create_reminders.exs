defmodule App.Repo.Migrations.CreateReminders do
  use Ecto.Migration

  # One row per reminder emailed to a member about an activity they haven't replied to
  # (#444): who sent it, when, which round, and whether Cloudflare took it. At most two
  # rounds per member and activity. #166's schedule can send them later, with no user.
  def change do
    create table(:reminders) do
      add :team_id, references(:teams), null: false
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :sent_by_user_id, references(:users, on_delete: :nilify_all)
      add :sent_at, :utc_datetime_usec, null: false
      add :round, :integer, null: false
      add :status, :string, null: false
      add :error, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:reminders, [:activity_id, :member_id, :round])
    create index(:reminders, [:team_id])
    create index(:reminders, [:member_id])
  end
end
