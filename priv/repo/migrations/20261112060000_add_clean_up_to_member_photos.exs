defmodule App.Repo.Migrations.AddCleanUpToMemberPhotos do
  use Ecto.Migration

  # Clean up (#1031): a waiting photo keeps both the photo as taken and the cleaned-up
  # one, and whether the Clean up switch was on, which says which of them the square is
  # placed on. A photo added with Clean up off, or when it did not answer, has no
  # cleaned-up copy.
  def change do
    alter table(:member_photos) do
      add :clean_up, :boolean, null: false, default: false
      add :cleaned_width, :integer
      add :cleaned_height, :integer
    end

    alter table(:member_photo_files) do
      add :cleaned_bytes, :binary
    end
  end
end
