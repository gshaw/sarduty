defmodule App.Repo.Migrations.CreateChoreEvents do
  use Ecto.Migration

  # Chore events (#341): one D4H event per month and chore category, rebuilt from its
  # accepted chores each night it needs a send.
  def change do
    create table(:chore_events) do
      add :team_id, references(:teams), null: false
      add :chore_category_id, references(:chore_categories), null: false
      add :month, :date, null: false
      add :d4h_activity_id, :integer
      add :needs_send, :boolean, null: false, default: false
      add :sent_at, :utc_datetime_usec
      add :send_error, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:chore_events, [:team_id, :chore_category_id, :month])

    alter table(:chores) do
      add :chore_event_id, references(:chore_events, on_delete: :nilify_all)
    end

    create index(:chores, [:chore_event_id])
  end
end
