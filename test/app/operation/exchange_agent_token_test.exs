defmodule App.Operation.ExchangeAgentTokenTest do
  # Codes and refresh tokens for tokens (#761).
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Model.AgentConnection
  alias App.Model.Member
  alias App.Operation.AuthorizeAgent
  alias App.Operation.ExchangeAgentToken
  alias App.Operation.RegisterAgentClient
  alias App.Operation.SetTeamMCP

  @now ~U[2026-10-31 12:00:00.000000Z]

  setup do
    admin = make_admin(AccountsFixtures.user_fixture())
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, team} = SetTeamMCP.call(team, true, admin)
    %{user: user, team: team}
  end

  defp refresh(team, token, now, extra \\ %{}) do
    params = Map.merge(%{"grant_type" => "refresh_token", "refresh_token" => token}, extra)
    ExchangeAgentToken.call(team, "https://sarduty.com/teams/x/mcp", params, now)
  end

  describe "pure checks" do
    test "pkce_ok?/2 matches only the verifier's S256 hash" do
      {verifier, challenge} = pkce_fixture()
      assert ExchangeAgentToken.pkce_ok?(verifier, challenge)
      refute ExchangeAgentToken.pkce_ok?(verifier <> "x", challenge)
      refute ExchangeAgentToken.pkce_ok?(nil, challenge)
    end

    test "refresh_match/3: current, previous within 60 seconds, then expired" do
      connection = %AgentConnection{
        refresh_token_hash: "new",
        previous_refresh_token_hash: "old",
        previous_refresh_expires_at: DateTime.add(@now, 60),
        refreshed_at: @now
      }

      assert ExchangeAgentToken.refresh_match(connection, "new", @now) == :current

      assert ExchangeAgentToken.refresh_match(connection, "old", DateTime.add(@now, 59)) ==
               :previous

      assert ExchangeAgentToken.refresh_match(connection, "old", DateTime.add(@now, 60)) ==
               :expired

      assert ExchangeAgentToken.refresh_match(connection, "other", @now) == nil
    end

    test "refresh_match/3: a refresh token ends after 90 days without a refresh" do
      connection = %AgentConnection{refresh_token_hash: "new", refreshed_at: @now}

      assert ExchangeAgentToken.refresh_match(connection, "new", DateTime.add(@now, 89, :day)) ==
               :current

      assert ExchangeAgentToken.refresh_match(connection, "new", DateTime.add(@now, 90, :day)) ==
               :expired
    end
  end

  test "a code trades once for an hour's access token and a refresh token", ctx do
    %{tokens: tokens, connection: connection} = agent_connection_fixture(ctx.team, ctx.user, @now)

    assert tokens["token_type"] == "Bearer"
    assert tokens["expires_in"] == 3600
    assert "sarduty_at_" <> _ = tokens["access_token"]
    assert "sarduty_rt_" <> _ = tokens["refresh_token"]
    assert connection.connected_at == @now
    assert connection.access_expires_at == DateTime.add(@now, 3600)
    refute connection.code_hash
  end

  test "a code fails when expired, reused, or with the wrong verifier", ctx do
    %{team: team, user: user} = ctx

    {:ok, client} =
      RegisterAgentClient.call(%{"redirect_uris" => ["http://localhost:1/cb"]})

    {verifier, challenge} = pkce_fixture()

    request = %{
      client: client,
      name: "A",
      redirect_uri: "http://localhost:1/cb",
      state: nil,
      code_challenge: challenge
    }

    {:ok, url} = AuthorizeAgent.allow(team, user, request, @now)
    code = URI.decode_query(URI.parse(url).query)["code"]
    params = %{"grant_type" => "authorization_code", "code" => code, "code_verifier" => verifier}

    assert {:error, "invalid_grant", _} =
             ExchangeAgentToken.call(team, "u", Map.put(params, "code_verifier", "wrong"), @now)

    assert {:error, "invalid_grant", _} =
             ExchangeAgentToken.call(team, "u", params, DateTime.add(@now, 10, :minute))

    assert {:error, "invalid_grant", _} =
             ExchangeAgentToken.call(team, "u", Map.put(params, "client_id", "other"), @now)

    assert {:ok, _tokens} = ExchangeAgentToken.call(team, "u", params, @now)
    assert {:error, "invalid_grant", _} = ExchangeAgentToken.call(team, "u", params, @now)
  end

  test "a code on one team never works on another", ctx do
    %{user: other_user, team: other} = user_with_team_fixture()

    {:ok, client} =
      RegisterAgentClient.call(%{"redirect_uris" => ["http://localhost:1/cb"]})

    {verifier, challenge} = pkce_fixture()

    request = %{
      client: client,
      name: "A",
      redirect_uri: "http://localhost:1/cb",
      state: nil,
      code_challenge: challenge
    }

    {:ok, other} = SetTeamMCP.call(other, true, make_admin(AccountsFixtures.user_fixture()))
    {:ok, url} = AuthorizeAgent.allow(other, other_user, request, @now)
    code = URI.decode_query(URI.parse(url).query)["code"]
    params = %{"grant_type" => "authorization_code", "code" => code, "code_verifier" => verifier}

    assert {:error, "invalid_grant", _} = ExchangeAgentToken.call(ctx.team, "u", params, @now)
  end

  test "refreshing rotates, and the old refresh token works for 60 seconds", ctx do
    %{tokens: first} = agent_connection_fixture(ctx.team, ctx.user, @now)
    later = DateTime.add(@now, 2, :hour)

    assert {:ok, second} = refresh(ctx.team, first["refresh_token"], later)
    refute second["refresh_token"] == first["refresh_token"]
    refute second["access_token"] == first["access_token"]

    # The agent lost the answer and asks again with the old one.
    assert {:ok, third} = refresh(ctx.team, first["refresh_token"], DateTime.add(later, 30))
    assert {:ok, _} = refresh(ctx.team, third["refresh_token"], DateTime.add(later, 40))

    assert {:error, "invalid_grant", _} =
             refresh(ctx.team, first["refresh_token"], DateTime.add(later, 61))
  end

  test "an old access token stops working once refreshed", ctx do
    %{tokens: first, connection: connection} = agent_connection_fixture(ctx.team, ctx.user, @now)
    {:ok, second} = refresh(ctx.team, first["refresh_token"], @now)

    refute AgentConnection.get_by_access_token(first["access_token"], @now)
    assert AgentConnection.get_by_access_token(second["access_token"], @now).id == connection.id
  end

  test "no refresh after a disconnect, or for someone no longer a team admin", ctx do
    %{tokens: tokens, connection: connection} = agent_connection_fixture(ctx.team, ctx.user, @now)

    manager = Repo.get_by!(Member, team_id: ctx.team.id, email: ctx.user.email)
    Member.update!(manager, %{d4h_permission: 2})
    assert {:error, "invalid_grant", _} = refresh(ctx.team, tokens["refresh_token"], @now)

    Member.update!(manager, %{d4h_permission: 0})
    AgentConnection.revoke!(connection, @now)
    assert {:error, "invalid_grant", _} = refresh(ctx.team, tokens["refresh_token"], @now)
  end

  test "an unknown grant type is refused", ctx do
    assert {:error, "unsupported_grant_type", _} =
             ExchangeAgentToken.call(ctx.team, "u", %{"grant_type" => "password"}, @now)
  end
end
