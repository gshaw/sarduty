defmodule App.Repo.Migrations.AddWhiteboardChoiceToTeams do
  use Ecto.Migration

  # The whiteboard (#515) becomes a feature a team turns on. The old column kept whether
  # D4H answers for it, and moves to d4h_whiteboard. A team that has notes already uses
  # it, so it starts on; every other team starts off.
  def up do
    rename table(:teams), :whiteboard_enabled, to: :d4h_whiteboard

    alter table(:teams) do
      add :whiteboard_enabled, :boolean, null: false, default: false
    end

    execute """
    UPDATE teams SET whiteboard_enabled = 1
    WHERE d4h_whiteboard AND id IN (SELECT team_id FROM whiteboard_notes)
    """
  end

  def down do
    alter table(:teams) do
      remove :whiteboard_enabled
    end

    rename table(:teams), :d4h_whiteboard, to: :whiteboard_enabled
  end
end
