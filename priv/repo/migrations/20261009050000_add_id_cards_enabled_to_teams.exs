defmodule App.Repo.Migrations.AddIdCardsEnabledToTeams do
  use Ecto.Migration

  # Only teams a SAR Duty admin turns on may issue ID cards: anyone can sign up a team
  # on SAR Duty Records, and a card verifies on verify.sarduty.com. Every team here now
  # is on D4H and keeps issuing; new teams start off.
  def up do
    alter table(:teams) do
      add :id_cards_enabled, :boolean, null: false, default: false
    end

    flush()
    execute "UPDATE teams SET id_cards_enabled = 1"
  end

  def down do
    alter table(:teams) do
      remove :id_cards_enabled
    end
  end
end
