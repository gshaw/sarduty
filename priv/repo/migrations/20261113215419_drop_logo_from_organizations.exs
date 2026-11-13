defmodule App.Repo.Migrations.DropLogoFromOrganizations do
  use Ecto.Migration

  # Organization logos are in the file store since #1067, and production copied each one
  # on 2026-11-13. Down brings back an empty column, not the logos.
  def change do
    alter table(:organizations) do
      remove :logo, :binary
    end
  end
end
