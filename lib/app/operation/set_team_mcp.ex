defmodule App.Operation.SetTeamMCP do
  @moduledoc """
  Turns MCP on or off for a team (#28). A team admin does it on the team's MCP tokens page
  in team settings (#595), and a SAR Duty admin on the team's admin page,
  /admin/teams/:id (#513). Turning it off revokes every token on the team, so turning it
  back on never wakes old tokens.
  """

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, team}`, or `{:error, :not_allowed}` for someone who isn't a team admin."
  def call(%Team{} = team, enabled, %User{} = user, now \\ DateTime.utc_now())
      when is_boolean(enabled) do
    if allowed?(team, user, now), do: set(team, enabled, user), else: {:error, :not_allowed}
  end

  defp allowed?(_team, %User{is_admin: true}, _now), do: true
  defp allowed?(team, user, now), do: Team.managed_by?(team, user.email, now)

  defp set(team, enabled, user) do
    Repo.transaction(fn ->
      team = team |> Ecto.Changeset.change(mcp_enabled: enabled) |> Repo.update!()
      revoked = if enabled, do: 0, else: MCPToken.revoke_all!(team, DateTime.utc_now())
      kind = if enabled, do: :mcp_turned_on, else: :mcp_turned_off
      Event.record!(kind, team_id: team.id, user_id: user.id, data: %{revoked: revoked})
      team
    end)
  end
end
