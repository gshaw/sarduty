defmodule App.Repo.Migrations.RemoveMcp do
  use Ecto.Migration

  # AI writing replaces connecting an agent (#1087): the MCP endpoint, its OAuth
  # connections, and its call log go, with the team switch. Their events stay. Down
  # brings the tables back empty, as 20261102200000 left them, and the switch off.
  def up do
    drop table(:mcp_calls)
    drop table(:agent_connections)
    drop table(:agent_clients)

    alter table(:teams) do
      remove :mcp_enabled
    end
  end

  def down do
    alter table(:teams) do
      add :mcp_enabled, :boolean, null: false, default: false
    end

    create table(:agent_clients) do
      add :client_id, :string, null: false
      add :name, :string
      add :redirect_uris, {:array, :string}, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:agent_clients, [:client_id])

    create table(:agent_connections) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :agent_client_id, references(:agent_clients, on_delete: :nilify_all)
      add :name, :string, null: false
      add :redirect_uri, :string, null: false
      add :code_hash, :binary
      add :code_challenge, :string
      add :code_expires_at, :utc_datetime_usec
      add :refresh_token_hash, :binary
      add :previous_refresh_token_hash, :binary
      add :previous_refresh_expires_at, :utc_datetime_usec
      add :refreshed_at, :utc_datetime_usec
      add :access_token_hash, :binary
      add :access_expires_at, :utc_datetime_usec
      add :connected_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:agent_connections, [:code_hash])
    create unique_index(:agent_connections, [:refresh_token_hash])
    create unique_index(:agent_connections, [:access_token_hash])
    create index(:agent_connections, [:previous_refresh_token_hash])
    create index(:agent_connections, [:team_id])
    create index(:agent_connections, [:user_id])
    create index(:agent_connections, [:agent_client_id])

    create table(:mcp_calls) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :agent_connection_id, references(:agent_connections, on_delete: :nilify_all)
      add :tool, :string, null: false
      add :arguments, :map, null: false, default: %{}
      add :row_count, :integer
      add :error, :string
      add :duration_ms, :integer
      add :called_at, :utc_datetime_usec, null: false
    end

    create index(:mcp_calls, [:called_at])
    create index(:mcp_calls, [:team_id, :called_at])
    create index(:mcp_calls, [:agent_connection_id])
  end
end
