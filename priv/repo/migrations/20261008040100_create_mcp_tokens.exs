defmodule App.Repo.Migrations.CreateMcpTokens do
  use Ecto.Migration

  # A manager's personal token for the MCP endpoint (#28). Only its SHA-256 hash is
  # stored. Revoked tokens are kept, so the call log can still name them.
  def change do
    create table(:mcp_tokens) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:mcp_tokens, [:token_hash])
    create index(:mcp_tokens, [:team_id])
    create index(:mcp_tokens, [:user_id])
  end
end
