defmodule App.Operation.DisconnectAgent do
  @moduledoc """
  Disconnects an AI agent, found through the team (#761): its access token and refresh
  token stop working at once. Anyone who can open the team's settings may disconnect
  any of its agents, so a team admin can stop a colleague's.
  """

  alias App.Accounts.User
  alias App.Model.AgentConnection
  alias App.Model.Event
  alias App.Model.Team

  def call(%Team{} = team, id, %User{} = user, now \\ DateTime.utc_now()) do
    case AgentConnection.find_connected(team, id) do
      nil ->
        {:error, :not_found}

      connection ->
        connection = AgentConnection.revoke!(connection, now)

        Event.record!(:agent_disconnected,
          team_id: team.id,
          user_id: user.id,
          data: %{agent_connection_id: connection.id}
        )

        {:ok, connection}
    end
  end
end
