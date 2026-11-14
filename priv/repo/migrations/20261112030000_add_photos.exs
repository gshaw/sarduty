defmodule App.Repo.Migrations.AddPhotos do
  use Ecto.Migration

  # Photos (#1028): the team's switch, off until a team admin turns it on, and when SAR
  # Duty last set or removed a member's photo, which versions the photo's URL so a
  # browser that cached the old one loads the new one.
  def change do
    alter table(:teams) do
      add :photos_enabled, :boolean, null: false, default: false
    end

    alter table(:members) do
      add :photo_changed_at, :utc_datetime
    end
  end
end
