defmodule App.Repo.Migrations.AddRetiringD4hGroupIdToTeams do
  use Ecto.Migration

  # The team's Retiring group (#514), a D4H group id like watch_d4h_group_id.
  def change do
    alter table(:teams) do
      add :retiring_d4h_group_id, :integer
    end
  end
end
