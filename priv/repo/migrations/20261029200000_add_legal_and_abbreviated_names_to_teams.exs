defmodule App.Repo.Migrations.AddLegalAndAbbreviatedNamesToTeams do
  use Ecto.Migration

  # A team's legal name, for tax credit letters and the back of ID cards, and its
  # abbreviated name, for texts (#738). Both start as the team's name; Needs attention
  # asks team admins to shorten the abbreviation.
  def up do
    alter table(:teams) do
      add :legal_name, :string
      add :abbreviated_name, :string
    end

    execute "UPDATE teams SET legal_name = name, abbreviated_name = name"
  end

  def down do
    alter table(:teams) do
      remove :legal_name
      remove :abbreviated_name
    end
  end
end
