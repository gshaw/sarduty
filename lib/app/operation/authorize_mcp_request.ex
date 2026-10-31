defmodule App.Operation.AuthorizeMCPRequest do
  @moduledoc """
  The MCP endpoint's check on every request (#28, #761). An access token passes when it
  is not expired, its connection is not revoked, its team has Agents on, and its user
  still passes the D4H bar for the team (App.Model.Team.managed_by?/3). So losing Owner
  or Editor in D4H ends the agent's access after the next refresh. The token decides
  the team.
  """

  alias App.Model.AgentConnection
  alias App.Model.Team

  def call(token, now \\ DateTime.utc_now())

  def call(token, now) when is_binary(token) and token != "" do
    with %AgentConnection{} = connection <- AgentConnection.get_by_access_token(token, now),
         true <- Team.managed_by?(connection.team, connection.user.email, now) do
      {:ok, AgentConnection.touch!(connection, now)}
    else
      _no -> :error
    end
  end

  def call(_token, _now), do: :error
end
