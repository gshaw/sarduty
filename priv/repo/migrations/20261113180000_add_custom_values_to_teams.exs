defmodule App.Repo.Migrations.AddCustomValuesToTeams do
  use Ecto.Migration

  # The team's own custom field values (#1056 step 5), from D4H's GET /teams/{id}, keyed
  # like a record's: the D4H field id as a string. Nil means not copied yet.
  def change do
    alter table(:teams) do
      add :custom_values, :map
    end
  end
end
