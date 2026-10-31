defmodule App.Operation.SetTeamMCP do
  @moduledoc """
  Turns Agents on or off for a team (#28, #761); the column is still `mcp_enabled`. Only
  a SAR Duty admin does it, on the team's admin page, /admin/teams/:id (#513), as with
  ID cards: an agent reads the team's people, so SAR Duty checks the team first. Team
  settings' Features tab shows it as on or off. Turning it off revokes every connected
  agent on the team; the rows stay, so turning it back on wakes none of them.
  """

  alias App.Accounts.User
  alias App.Model.AgentConnection
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, team}`, or `{:error, :not_allowed}` for someone who isn't a SAR Duty admin."
  def call(%Team{} = team, enabled, %User{} = user) when is_boolean(enabled) do
    if user.is_admin, do: set(team, enabled, user), else: {:error, :not_allowed}
  end

  defp set(team, enabled, user) do
    Repo.transaction(fn ->
      team = team |> Ecto.Changeset.change(mcp_enabled: enabled) |> Repo.update!()
      revoked = if enabled, do: 0, else: AgentConnection.revoke_all!(team, DateTime.utc_now())
      kind = if enabled, do: :mcp_turned_on, else: :mcp_turned_off
      Event.record!(kind, team_id: team.id, user_id: user.id, data: %{revoked: revoked})
      team
    end)
  end
end
