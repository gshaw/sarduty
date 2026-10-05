defmodule App.Repo.Migrations.CreateShortLinks do
  use Ecto.Migration

  # Short links: /s/<code> redirects to a longer path. The first use is the attendance
  # link (#139). The target can hold a secret token, so it is stored encrypted.
  def change do
    create table(:short_links) do
      add :code, :string, null: false
      add :target, :binary, null: false
      add :team_id, references(:teams)
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:short_links, [:code])

    alter table(:attendance_links) do
      add :short_link_id, references(:short_links, on_delete: :nilify_all)
    end
  end
end
