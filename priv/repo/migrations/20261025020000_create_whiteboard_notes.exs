defmodule App.Repo.Migrations.CreateWhiteboardNotes do
  use Ecto.Migration

  # A copy of the team's D4H whiteboard (#515). Notes are not history: the sync replaces
  # them. whiteboard_enabled goes false when D4H answers 403 with the module off.
  def change do
    create table(:whiteboard_notes) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :d4h_whiteboard_note_id, :integer, null: false
      add :text, :string, null: false
      add :url, :string
      add :important, :boolean, null: false, default: false
      add :owner_kind, :string, null: false, default: "team"
      add :archived_at, :utc_datetime
      add :d4h_created_at, :utc_datetime
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:whiteboard_notes, [:team_id, :d4h_whiteboard_note_id])

    alter table(:teams) do
      add :whiteboard_enabled, :boolean, null: false, default: true
    end
  end
end
