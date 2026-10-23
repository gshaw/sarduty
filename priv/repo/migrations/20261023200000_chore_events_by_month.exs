defmodule App.Repo.Migrations.ChoreEventsByMonth do
  use Ecto.Migration

  # Chores v2: one D4H event per chore category and month, not one per send. Each event
  # takes the month of its latest accepted chore, or the month it was made when it has
  # none. Every event has changes to send: the next send moves chores done in another
  # month to that month's event, merges two events of one month, and retitles each for
  # its month. Nothing locks an event: D4H's `approved` only mirrors `published` (#358).
  def up do
    alter table(:chore_events) do
      add :month, :date
    end

    execute """
    UPDATE chore_events SET
      month = coalesce(
        (SELECT substr(max(c.date), 1, 7) || '-01' FROM chores c
          WHERE c.chore_event_id = chore_events.id AND c.status = 'accepted'),
        substr(inserted_at, 1, 7) || '-01'),
      needs_send = 1
    """

    alter table(:chore_events) do
      remove :year
      remove :locked
    end
  end

  def down do
    alter table(:chore_events) do
      add :year, :integer, null: false, default: 0
      add :locked, :boolean, null: false, default: false
    end

    execute "UPDATE chore_events SET year = CAST(substr(month, 1, 4) AS INTEGER)"

    alter table(:chore_events) do
      remove :month
    end
  end
end
