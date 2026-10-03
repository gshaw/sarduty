defmodule App.Repo.Migrations.AddD4HAccessKeyOwnerToTeams do
  use Ecto.Migration

  # The name of the D4H member whose token the team key is, from D4H `whoami`. Nil until
  # the key is next saved or the next refresh runs.
  def change do
    alter table(:teams) do
      add :d4h_access_key_owner, :string
    end
  end
end
