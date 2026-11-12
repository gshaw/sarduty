defmodule App.Repo.Migrations.AddHasPhotoToMembers do
  use Ecto.Migration

  # Whether the team's records had a photo of the member at the last check (#1012). An
  # ID card needs one. False until the first nightly check, so no new cards go out
  # until then.
  def change do
    alter table(:members) do
      add :has_photo, :boolean, null: false, default: false
    end
  end
end
