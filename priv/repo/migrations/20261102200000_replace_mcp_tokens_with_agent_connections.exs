defmodule App.Repo.Migrations.ReplaceMcpTokensWithAgentConnections do
  use Ecto.Migration

  # cspell:ignore fkey (ecto_sqlite3's suffix for a foreign key's constraint name)

  # AI agents connect with OAuth (#761) in place of personal MCP tokens. A registration
  # is an agent_clients row; each agent an admin allows is an agent_connections row, with
  # its code, refresh token, and access token as SHA-256 hashes. Live tokens end here and
  # their owners reconnect. SQLite can't drop `mcp_token_id`, a foreign key, so mcp_calls
  # is rebuilt, as #475 rebuilt attendance_scans; old calls keep their team and user.
  def up do
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

    execute("""
    CREATE TABLE "mcp_calls_new" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "team_id" INTEGER NOT NULL CONSTRAINT "mcp_calls_team_id_fkey" REFERENCES "teams"("id") ON DELETE CASCADE,
      "user_id" INTEGER CONSTRAINT "mcp_calls_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
      "agent_connection_id" INTEGER CONSTRAINT "mcp_calls_agent_connection_id_fkey" REFERENCES "agent_connections"("id") ON DELETE SET NULL,
      "tool" TEXT NOT NULL,
      "arguments" TEXT DEFAULT ('{}') NOT NULL,
      "row_count" INTEGER,
      "error" TEXT,
      "duration_ms" INTEGER,
      "called_at" TEXT NOT NULL
    )
    """)

    columns = "id, team_id, user_id, tool, arguments, row_count, error, duration_ms, called_at"
    execute("INSERT INTO mcp_calls_new (#{columns}) SELECT #{columns} FROM mcp_calls")
    execute("DROP TABLE mcp_calls")
    execute("ALTER TABLE mcp_calls_new RENAME TO mcp_calls")
    create index(:mcp_calls, [:called_at])
    create index(:mcp_calls, [:team_id, :called_at])
    create index(:mcp_calls, [:agent_connection_id])

    drop table(:mcp_tokens)
  end

  # Tokens don't come back: the table returns empty, and calls lose their connection.
  def down do
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

    execute("""
    CREATE TABLE "mcp_calls_new" (
      "id" INTEGER PRIMARY KEY AUTOINCREMENT,
      "team_id" INTEGER NOT NULL CONSTRAINT "mcp_calls_team_id_fkey" REFERENCES "teams"("id") ON DELETE CASCADE,
      "user_id" INTEGER CONSTRAINT "mcp_calls_user_id_fkey" REFERENCES "users"("id") ON DELETE SET NULL,
      "mcp_token_id" INTEGER CONSTRAINT "mcp_calls_mcp_token_id_fkey" REFERENCES "mcp_tokens"("id") ON DELETE SET NULL,
      "tool" TEXT NOT NULL,
      "arguments" TEXT DEFAULT ('{}') NOT NULL,
      "row_count" INTEGER,
      "error" TEXT,
      "duration_ms" INTEGER,
      "called_at" TEXT NOT NULL
    )
    """)

    columns = "id, team_id, user_id, tool, arguments, row_count, error, duration_ms, called_at"
    execute("INSERT INTO mcp_calls_new (#{columns}) SELECT #{columns} FROM mcp_calls")
    execute("DROP TABLE mcp_calls")
    execute("ALTER TABLE mcp_calls_new RENAME TO mcp_calls")
    create index(:mcp_calls, [:called_at])
    create index(:mcp_calls, [:team_id, :called_at])

    drop table(:agent_connections)
    drop table(:agent_clients)
  end
end
