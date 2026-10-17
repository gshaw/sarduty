defmodule App.Repo.Migrations.AddTeamsNotSeenDays do
  use Ecto.Migration

  # Needs attention lists members not seen at an activity in this many days (#247). Null
  # turns the item off.
  def change do
    alter table(:teams) do
      add :not_seen_days, :integer, default: 90
    end
  end
end
