defmodule App.Repo.Migrations.CreateActivityUpdates do
  use Ecto.Migration

  # An update a team admin emails to members on an activity (#609), a row per member.
  # A send's rows share their `sent_at` and message.
  def change do
    create table(:activity_updates) do
      add :team_id, references(:teams), null: false
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :sent_by_user_id, references(:users, on_delete: :nilify_all)
      add :message, :text, null: false
      add :sent_at, :utc_datetime_usec, null: false
      add :status, :string, null: false
      add :error, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:activity_updates, [:team_id])
    create index(:activity_updates, [:member_id])
  end
end
