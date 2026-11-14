defmodule App.Repo.Migrations.AddEditsToActivityPhotos do
  use Ecto.Migration

  # Edit photo (#1032, part 8): a team admin's one edit of an accepted photo, kept as
  # settings, never as a new original. `turns` are quarter turns clockwise, `angle` the
  # straightening in degrees, and `clean_up` whether Clean up is on. The copies to show
  # and for tiles are made again from the original with them.
  def change do
    alter table(:activity_photos) do
      add :turns, :integer, null: false, default: 0
      add :angle, :float, null: false, default: 0.0
      add :clean_up, :boolean, null: false, default: false
      add :edited_by_user_id, references(:users, on_delete: :nilify_all)
      add :edited_at, :utc_datetime_usec
    end
  end
end
