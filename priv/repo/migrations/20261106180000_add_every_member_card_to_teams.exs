defmodule App.Repo.Migrations.AddEveryMemberCardToTeams do
  use Ecto.Migration

  # Every member gets a card (#893): a team admin's switch that gives every member in
  # good standing an ID card, and each new member theirs at the next refresh.
  def change do
    alter table(:teams) do
      add :every_member_card, :boolean, null: false, default: false
    end
  end
end
