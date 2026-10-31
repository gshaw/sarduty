defmodule App.Repo.Migrations.AddD4HPermissionsToTeams do
  use Ecto.Migration

  # What D4H lets the team's key do (#727): whoami's permission map, and when SAR Duty
  # last read it. Nil for a Records team, and for a D4H team until its key is checked.
  def change do
    alter table(:teams) do
      add :d4h_permissions, :map
      add :d4h_permissions_checked_at, :utc_datetime_usec
    end
  end
end
