defmodule App.Repo.Migrations.AddOutboxSeenAtToDemoTeams do
  use Ecto.Migration

  # When the demo's Outbox list was last opened (#857): what arrived after it is new.
  def change do
    alter table(:demo_teams) do
      add :outbox_seen_at, :utc_datetime_usec
    end
  end
end
