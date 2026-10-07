defmodule App.Operation.SetTeamMCP do
  @moduledoc """
  Turns the MCP trial on or off for a team (#28). Only an admin does this, from
  /admin/mcp. Turning it off revokes every token on the team, so turning it back on
  never wakes old tokens.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, enabled, %User{is_admin: true} = admin, now \\ DateTime.utc_now())
      when is_boolean(enabled) do
    Repo.transaction(fn ->
      team = team |> Ecto.Changeset.change(mcp_enabled: enabled) |> Repo.update!()
      revoked = if enabled, do: 0, else: MCPToken.revoke_all!(team, now)
      kind = if enabled, do: :mcp_turned_on, else: :mcp_turned_off
      Event.record!(kind, team_id: team.id, user_id: admin.id, data: %{revoked: revoked})
      team
    end)
  end
end
