defmodule App.Repo.Migrations.CreateAiWriting do
  use Ecto.Migration

  # AI writing on the Claude API. ai_settings is one row, SAR Duty's own: who gets AI
  # writing, which model, and the monthly budget. ai_asks is one row per ask, the usage
  # and cost Adminland › AI writing shows; it replaces mcp_calls once MCP goes.
  def change do
    create table(:ai_settings) do
      add :access, :string, null: false, default: "off"
      add :model, :string, null: false
      add :monthly_budget_cents, :integer, null: false
      add :updated_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create table(:ai_asks) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :ask, :text
      add :model, :string, null: false
      add :input_tokens, :integer, null: false, default: 0
      add :cache_write_tokens, :integer, null: false, default: 0
      add :cache_read_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cost_microdollars, :integer, null: false, default: 0
      add :turns, :integer, null: false, default: 0
      add :duration_ms, :integer
      add :outcome, :string, null: false
      add :asked_at, :utc_datetime_usec, null: false
    end

    create index(:ai_asks, [:asked_at])
    create index(:ai_asks, [:team_id, :asked_at])
    create index(:ai_asks, [:user_id])
  end
end
