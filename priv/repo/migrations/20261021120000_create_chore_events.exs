defmodule App.Repo.Migrations.CreateChoreEvents do
  use Ecto.Migration

  # Chore events (#341): one D4H event per chore category and year in a send a team admin
  # makes. A sent chore points at its event; changing it marks the event to send again.
  def change do
    create table(:chore_events) do
      add :team_id, references(:teams), null: false
      add :chore_category_id, references(:chore_categories), null: false
      add :year, :integer, null: false
      add :d4h_activity_id, :integer
      add :needs_send, :boolean, null: false, default: false
      add :sent_at, :utc_datetime_usec
      add :send_note, :string
      add :locked, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chore_events, [:team_id])

    alter table(:chores) do
      add :chore_event_id, references(:chore_events, on_delete: :nilify_all)
    end

    create index(:chores, [:chore_event_id])
  end
end
