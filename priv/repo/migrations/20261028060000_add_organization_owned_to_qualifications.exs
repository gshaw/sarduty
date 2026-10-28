defmodule App.Repo.Migrations.AddOrganizationOwnedToQualifications do
  use Ecto.Migration

  # A D4H qualification the team's organization owns, like a group's (#652). The next
  # refresh fills it in.
  def change do
    alter table(:qualifications) do
      add :organization_owned, :boolean, null: false, default: false
    end
  end
end
