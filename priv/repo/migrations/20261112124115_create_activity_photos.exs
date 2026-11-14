defmodule App.Repo.Migrations.CreateActivityPhotos do
  use Ecto.Migration

  # A photo someone added to an activity (#1032). It waits until a team admin accepts
  # it. The row holds who added it, the send's caption and whether the team may post
  # it, and `file_token`, which names its files in the file store. No file is in the
  # database.
  def change do
    create table(:activity_photos) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :activity_id, references(:activities, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :nilify_all)
      add :added_by_user_id, references(:users, on_delete: :nilify_all)
      add :status, :string, null: false, default: "waiting"
      add :file_token, :string, null: false
      add :width, :integer, null: false
      add :height, :integer, null: false
      add :caption, :text
      add :may_post, :boolean, null: false, default: false
      add :accepted_by_user_id, references(:users, on_delete: :nilify_all)
      add :accepted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:activity_photos, [:team_id, :status])
    create index(:activity_photos, [:activity_id])
    create index(:activity_photos, [:member_id])
    create unique_index(:activity_photos, [:file_token])
  end
end
