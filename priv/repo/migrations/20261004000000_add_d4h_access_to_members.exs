defmodule App.Repo.Migrations.AddD4HAccessToMembers do
  use Ecto.Migration

  # D4H's access level and status for each member, from the nightly sync (#57 phase 2).
  # Nil until the next refresh. The team key's own member id lets the SAR Duty account
  # be left out of the managers list.
  def change do
    alter table(:members) do
      add :d4h_permission, :integer
      add :d4h_status, :string
    end

    alter table(:teams) do
      add :d4h_access_key_member_id, :integer
    end
  end
end
