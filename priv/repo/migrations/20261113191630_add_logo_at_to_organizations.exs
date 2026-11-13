defmodule App.Repo.Migrations.AddLogoAtToOrganizations do
  use Ecto.Migration

  # An organization's logo moves to the file store (#1067). logo_at says it has one, and
  # when it was saved. The bin/prod task copy_organization_logos fills it; a later PR
  # drops the logo column.
  def change do
    alter table(:organizations) do
      add :logo_at, :utc_datetime_usec
    end
  end
end
