defmodule App.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  # A parent organization, like BCSARA, whose member teams' cards carry its name and logo.
  # The logo is a PNG in the row, so Litestream backs it up with everything else.
  def change do
    create table(:organizations) do
      add :name, :string, null: false
      add :short_name, :string, null: false
      add :slug, :string, null: false
      add :website, :string
      add :logo, :binary

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organizations, [:slug])

    alter table(:teams) do
      add :organization_id, references(:organizations, on_delete: :nilify_all)
    end

    create index(:teams, [:organization_id])
  end
end
