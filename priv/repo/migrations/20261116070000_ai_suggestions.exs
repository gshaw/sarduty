defmodule App.Repo.Migrations.AiSuggestions do
  use Ecto.Migration

  # AI writing suggests two or three next asks after each reply, on reports and on
  # forms, each with its own switch on Adminland › AI writing. Both start on.
  def change do
    alter table(:ai_settings) do
      add :suggest_reports, :boolean, null: false, default: true
      add :suggest_forms, :boolean, null: false, default: true
    end
  end
end
