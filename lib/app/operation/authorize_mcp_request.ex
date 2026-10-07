defmodule App.Operation.AuthorizeMCPRequest do
  @moduledoc """
  The MCP endpoint's check on every request (#28). A bearer token passes when it is not
  revoked, its team has MCP on, and its user still passes the D4H bar for the team
  (App.Model.Team.managed_by?/3). So losing Owner or Editor in D4H ends the token's
  access after the next refresh. The token decides the team.
  """

  alias App.Model.MCPToken
  alias App.Model.Team

  def call(token, now \\ DateTime.utc_now())

  def call(token, now) when is_binary(token) and token != "" do
    with %MCPToken{} = record <- MCPToken.get_live(token),
         true <- Team.managed_by?(record.team, record.user.email, now) do
      {:ok, MCPToken.touch!(record, now)}
    else
      _no -> :error
    end
  end

  def call(_token, _now), do: :error
end
