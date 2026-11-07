defmodule App.Repo.Migrations.AddCityAndPostalCodeToTeams do
  use Ecto.Migration

  # The team's city and postal code, apart from its mailing address (#950, step 9):
  # EMCR's Expense reimbursement request asks for each on its own line. Set in team
  # settings; nil until a team admin does.
  def change do
    alter table(:teams) do
      add :city, :string
      add :postal_code, :string
    end
  end
end
