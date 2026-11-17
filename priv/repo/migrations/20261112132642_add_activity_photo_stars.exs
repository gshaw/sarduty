defmodule App.Repo.Migrations.AddActivityPhotoStars do
  use Ecto.Migration

  # Stars and featured photos (#1033). A star is one login's on one photo, so the pair
  # is unique, and it goes with its photo. `featured_at` is when a team admin featured
  # the photo on its activity's Overview, and nil for one that is not.
  def change do
    create table(:activity_photo_stars) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      add :activity_photo_id, references(:activity_photos, on_delete: :delete_all), null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:activity_photo_stars, [:activity_photo_id, :user_id])
    create index(:activity_photo_stars, [:team_id, :user_id])

    alter table(:activity_photos) do
      add :featured_at, :utc_datetime_usec
    end
  end
end
