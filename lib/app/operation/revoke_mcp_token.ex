defmodule App.Operation.RevokeMCPToken do
  @moduledoc """
  Revokes an MCP token, found through the team (#28). Anyone who can open the team's
  settings may revoke any of its tokens, so a manager can stop a colleague's lost one.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.MCPToken
  alias App.Model.Team

  def call(%Team{} = team, id, %User{} = user, now \\ DateTime.utc_now()) do
    case MCPToken.find_live(team, id) do
      nil ->
        {:error, :not_found}

      token ->
        token = MCPToken.revoke!(token, now)

        Event.record!(:mcp_token_revoked,
          team_id: team.id,
          user_id: user.id,
          data: %{mcp_token_id: token.id}
        )

        {:ok, token}
    end
  end
end
