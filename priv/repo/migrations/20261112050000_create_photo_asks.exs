defmodule App.Repo.Migrations.CreatePhotoAsks do
  use Ecto.Migration

  # A team admin asking a member for a photo (#1030): who asked, when, and their message.
  # Open until `closed_at`, when the member's photo is added. A member has one open ask;
  # asking again moves its date.
  def change do
    create table(:photo_asks) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :asked_by_user_id, references(:users, on_delete: :nilify_all)
      add :message, :text
      add :asked_at, :utc_datetime_usec, null: false
      add :closed_at, :utc_datetime_usec
      add :email_status, :string, null: false, default: "queued"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:photo_asks, [:team_id])
    create unique_index(:photo_asks, [:member_id], where: "closed_at IS NULL")
  end
end
