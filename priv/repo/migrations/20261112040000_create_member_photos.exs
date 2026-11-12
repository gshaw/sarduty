defmodule App.Repo.Migrations.CreateMemberPhotos do
  use Ecto.Migration

  # A photo a member added of themselves (#1029), waiting for a team admin. The row keeps
  # where the member placed it, then who decided, when, and why. The photo as taken is in
  # its own table, so lists never load it, and is deleted once the photo is accepted or
  # declined.
  def change do
    create table(:member_photos) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "waiting"
      add :width, :integer, null: false
      add :height, :integer, null: false
      add :turns, :integer, null: false, default: 0
      add :x, :float, null: false, default: 0.5
      add :y, :float, null: false, default: 0.5
      add :side, :float, null: false, default: 1.0
      add :decline_reason, :string
      add :decline_message, :text
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:member_photos, [:team_id, :status])
    create index(:member_photos, [:member_id])

    create table(:member_photo_files) do
      add :member_photo_id, references(:member_photos, on_delete: :delete_all), null: false
      add :bytes, :binary, null: false
    end

    create unique_index(:member_photo_files, [:member_photo_id])
  end
end
