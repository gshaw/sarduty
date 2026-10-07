defmodule App.Repo.Migrations.CreateMcpCalls do
  use Ecto.Migration

  # Every MCP tool call, to watch the trial (#28). Pruned after 90 days with events.
  def change do
    create table(:mcp_calls) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :mcp_token_id, references(:mcp_tokens, on_delete: :nilify_all)
      add :tool, :string, null: false
      add :arguments, :map, null: false, default: %{}
      add :row_count, :integer
      add :error, :string
      add :duration_ms, :integer
      add :called_at, :utc_datetime_usec, null: false
    end

    create index(:mcp_calls, [:called_at])
    create index(:mcp_calls, [:team_id, :called_at])
  end
end
