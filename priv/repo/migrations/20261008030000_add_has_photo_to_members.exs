defmodule App.Repo.Migrations.AddHasPhotoToMembers do
  use Ecto.Migration

  # Whether D4H has a photo for the member (#205). Null until the refresh checks, since
  # D4H's member record doesn't say.
  def change do
    alter table(:members) do
      add :has_photo, :boolean
    end
  end
end
