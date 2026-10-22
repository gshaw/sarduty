defmodule App.Repo.Migrations.AddMemberEmergencyContacts do
  use Ecto.Migration

  # Each member's two emergency contacts, copied from D4H's member list (#423). A map
  # with "name", "relation", "primary_phone", and "secondary_phone". Nil until the
  # first sync after this copies them, which history skips.
  def change do
    alter table(:members) do
      add :primary_emergency_contact, :map
      add :secondary_emergency_contact, :map
    end
  end
end
