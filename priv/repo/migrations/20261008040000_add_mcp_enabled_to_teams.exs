defmodule App.Repo.Migrations.AddMcpEnabledToTeams do
  use Ecto.Migration

  # The MCP trial's switch (#28). Only an admin sets it, on /admin/mcp.
  def change do
    alter table(:teams) do
      add :mcp_enabled, :boolean, null: false, default: false
    end
  end
end
