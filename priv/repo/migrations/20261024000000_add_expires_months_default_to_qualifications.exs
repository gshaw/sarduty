defmodule App.Repo.Migrations.AddExpiresMonthsDefaultToQualifications do
  use Ecto.Migration

  # D4H's suggested length of an award (#493). The next refresh fills it in.
  def change do
    alter table(:qualifications) do
      add :expires_months_default, :integer
    end
  end
end
