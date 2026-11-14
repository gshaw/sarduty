defmodule App.Repo.Migrations.CreateActivityPhotoAsks do
  use Ecto.Migration

  # A team admin asking a member who attended an activity for their photos of it
  # (#1034): who asked, when, and their message. A member has one ask for an activity;
  # asking again moves its date.
  #
  # `members.photo_asks` is whether the member takes these emails, which they set in
  # account settings. Set in SAR Duty, never from D4H.
  def change do
    create table(:activity_photo_asks) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :asked_by_user_id, references(:users, on_delete: :nilify_all)
      add :message, :text
      add :asked_at, :utc_datetime_usec, null: false
      add :email_status, :string, null: false, default: "queued"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:activity_photo_asks, [:team_id])
    create unique_index(:activity_photo_asks, [:activity_id, :member_id])
    create index(:activity_photo_asks, [:member_id])

    alter table(:members) do
      add :photo_asks, :boolean, null: false, default: true
    end
  end
end
