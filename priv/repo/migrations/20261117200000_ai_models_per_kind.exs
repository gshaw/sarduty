defmodule App.Repo.Migrations.AiModelsPerKind do
  use Ecto.Migration

  # AI writing picks a model for reports and one for forms, and how many next asks AI
  # suggests on each, 0 to 4, in place of one model and two on/off switches. Reports keep
  # the model they had (Haiku, no longer offered, becomes Sonnet); forms start on Opus. A
  # switch that was on becomes 2 next asks. Asks a day, 100 in the code until now, is a
  # setting too.
  def up do
    alter table(:ai_settings) do
      add :report_model, :string, null: false, default: "claude-sonnet-5-5"
      add :form_model, :string, null: false, default: "claude-opus-5-5"
      add :report_next_asks, :integer, null: false, default: 2
      add :form_next_asks, :integer, null: false, default: 2
      add :asks_per_day, :integer, null: false, default: 100
    end

    execute """
    UPDATE ai_settings SET
      report_model = CASE WHEN model = 'claude-haiku-5-5' THEN 'claude-sonnet-5-5' ELSE model END,
      report_next_asks = CASE WHEN suggest_reports THEN 2 ELSE 0 END,
      form_next_asks = CASE WHEN suggest_forms THEN 2 ELSE 0 END
    """

    alter table(:ai_settings) do
      remove :model
      remove :suggest_reports
      remove :suggest_forms
    end
  end

  def down do
    alter table(:ai_settings) do
      add :model, :string, null: false, default: "claude-sonnet-5-5"
      add :suggest_reports, :boolean, null: false, default: true
      add :suggest_forms, :boolean, null: false, default: true
    end

    execute """
    UPDATE ai_settings SET
      model = report_model,
      suggest_reports = report_next_asks > 0,
      suggest_forms = form_next_asks > 0
    """

    alter table(:ai_settings) do
      remove :report_model
      remove :form_model
      remove :report_next_asks
      remove :form_next_asks
      remove :asks_per_day
    end
  end
end
