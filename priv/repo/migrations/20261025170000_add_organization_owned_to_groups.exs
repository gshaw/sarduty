defmodule App.Repo.Migrations.AddOrganizationOwnedToGroups do
  use Ecto.Migration

  # A D4H group the team's organization owns: the team's key can change its members,
  # never its title. The next full refresh fills it in.
  def change do
    alter table(:groups) do
      add :organization_owned, :boolean, null: false, default: false
    end
  end
end
