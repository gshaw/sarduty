defmodule App.Repo.Migrations.AddRecordsOrganizationId do
  use Ecto.Migration

  # The id SAR Duty Records answers for an organization it keeps, such as each demo's
  # WESARA and the dev WESARA (#1003). Its fields belong to it there.
  def change do
    alter table(:organizations) do
      add :records_organization_id, :integer
    end
  end
end
