defmodule App.Operation.CreateMCPToken do
  @moduledoc """
  Creates a manager's personal MCP token (#28). Only on a team with MCP on, and only for
  a user who passes the D4H bar for it: an admin who doesn't manage the team can't make
  one. The manager must promise to use it only with an AI
  service that doesn't train on their data. Returns the token once; the database keeps its hash.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, %User{} = user, params, now \\ DateTime.utc_now()) do
    if team.mcp_enabled and Team.managed_by?(team, user.email, now) do
      {token, changeset} = MCPToken.build(team, user, params)

      with {:ok, record} <- Repo.insert(changeset) do
        Event.record!(:mcp_token_created,
          team_id: team.id,
          user_id: user.id,
          data: %{mcp_token_id: record.id, no_training: true}
        )

        {:ok, token, record}
      end
    else
      {:error, :not_allowed}
    end
  end
end
