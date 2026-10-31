defmodule App.Model.AgentConnectionTest do
  # Turning Agents off, and the nightly clean-up of agents that never connected (#761).
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Model.AgentClient
  alias App.Model.AgentConnection
  alias App.Operation.RegisterAgentClient
  alias App.Operation.SetTeamMCP

  setup do
    admin = make_admin(AccountsFixtures.user_fixture())
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, team} = SetTeamMCP.call(team, true, admin)
    %{user: user, team: team, admin: admin}
  end

  test "turning Agents off revokes every connection and keeps the rows", ctx do
    %{connection: connection} = agent_connection_fixture(ctx.team, ctx.user)

    {:ok, _team} = SetTeamMCP.call(ctx.team, false, ctx.admin)

    assert Repo.reload!(connection).revoked_at
    assert AgentConnection.count_connected_by_team() == %{}
  end

  test "prunes, after a day, Allows never traded and registrations never connected", ctx do
    now = DateTime.utc_now()
    later = DateTime.add(now, 25, :hour)
    %{connection: connected, client: kept} = agent_connection_fixture(ctx.team, ctx.user, now)
    pending = connected |> Map.take([:team_id, :user_id, :name, :redirect_uri])
    pending = Repo.insert!(struct(AgentConnection, pending))
    {:ok, unused} = RegisterAgentClient.call(%{"redirect_uris" => ["http://localhost:1/cb"]})

    assert AgentConnection.prune_pending(now) == 0
    assert AgentConnection.prune_pending(later) == 1
    refute Repo.get(AgentConnection, pending.id)
    assert Repo.get(AgentConnection, connected.id)

    assert AgentClient.prune(later) == 1
    refute Repo.get(AgentClient, unused.id)
    assert Repo.get(AgentClient, kept.id)
  end
end
