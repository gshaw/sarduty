defmodule Web.OAuthControllerTest do
  # How an AI agent connects (#761): metadata, registration, tokens, and Allow, the way
  # an agent walks them. Web.MCPControllerTest covers what the token then reads.
  use Web.ConnCase

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.Model.AgentConnection
  alias App.Model.Event
  alias App.Operation.SetTeamMCP
  alias App.Repo

  @claude "https://claude.ai/api/mcp/auth_callback"

  setup do
    admin = make_admin(AccountsFixtures.user_fixture())
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, team} = SetTeamMCP.call(team, true, admin)
    %{user: user, team: team, admin: admin}
  end

  defp register(team, body) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post(~p"/teams/#{team}/oauth/register", Jason.encode!(body))
  end

  defp authorize_params(client_id, challenge, extra) do
    Map.merge(
      %{
        "client_id" => client_id,
        "redirect_uri" => @claude,
        "response_type" => "code",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256",
        "state" => "st8"
      },
      extra
    )
  end

  test "the whole flow: 401, metadata, register, Allow, token, then MCP", ctx do
    %{team: team, user: user} = ctx
    base = Web.Endpoint.url()
    mcp = "#{base}/teams/#{team.subdomain}/mcp"

    conn = post(build_conn(), ~p"/teams/#{team}/mcp", %{})
    [header] = get_resp_header(conn, "www-authenticate")
    [_, metadata_url] = Regex.run(~r/resource_metadata="([^"]+)"/, header)

    resource = build_conn() |> get(URI.parse(metadata_url).path) |> json_response(200)
    assert resource["resource"] == mcp
    assert resource["authorization_servers"] == ["#{base}/teams/#{team.subdomain}"]

    server =
      build_conn()
      |> get("/.well-known/oauth-authorization-server/teams/#{team.subdomain}")
      |> json_response(200)

    assert server["issuer"] == "#{base}/teams/#{team.subdomain}"
    assert server["code_challenge_methods_supported"] == ["S256"]
    assert server["token_endpoint_auth_methods_supported"] == ["none"]

    registered =
      team
      |> register(%{"client_name" => "Claude", "redirect_uris" => [@claude]})
      |> json_response(201)

    assert "sarduty_client_" <> _ = registered["client_id"]
    {verifier, challenge} = pkce_fixture()
    params = authorize_params(registered["client_id"], challenge, %{"resource" => mcp})

    conn =
      build_conn()
      |> log_in_user(user)
      |> post(~p"/teams/#{team}/oauth/authorize", Map.put(params, "decision", "allow"))

    location = redirected_to(conn)
    assert String.starts_with?(location, @claude <> "?")
    query = URI.decode_query(URI.parse(location).query)
    assert query["state"] == "st8"

    tokens =
      build_conn()
      |> post(~p"/teams/#{team}/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => query["code"],
        "code_verifier" => verifier,
        "client_id" => registered["client_id"],
        "redirect_uri" => @claude,
        "resource" => mcp
      })
      |> json_response(200)

    assert [event] = Repo.all_by(Event, kind: :agent_connected)
    assert event.data["warning_shown"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{tokens["access_token"]}")
      |> post(~p"/teams/#{team}/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

    assert json_response(conn, 200)["result"] == %{}

    connection = Repo.one!(AgentConnection)
    assert connection.name == "Claude"
    assert connection.user_id == user.id
  end

  test "Cancel sends the admin back with access denied, and connects nothing", ctx do
    registered = ctx.team |> register(%{"redirect_uris" => [@claude]}) |> json_response(201)
    {_verifier, challenge} = pkce_fixture()
    params = authorize_params(registered["client_id"], challenge, %{"decision" => "cancel"})

    conn =
      build_conn()
      |> log_in_user(ctx.user)
      |> post(~p"/teams/#{ctx.team}/oauth/authorize", params)

    query = URI.decode_query(URI.parse(redirected_to(conn)).query)
    assert query == %{"error" => "access_denied", "state" => "st8"}
    assert Repo.all(AgentConnection) == []
  end

  test "Allow from someone who isn't a team admin connects nothing", ctx do
    %{team: _member_team, user: member} = member_with_login_fixture()
    registered = ctx.team |> register(%{"redirect_uris" => [@claude]}) |> json_response(201)
    {_verifier, challenge} = pkce_fixture()
    params = authorize_params(registered["client_id"], challenge, %{"decision" => "allow"})

    conn =
      build_conn() |> log_in_user(member) |> post(~p"/teams/#{ctx.team}/oauth/authorize", params)

    assert URI.decode_query(URI.parse(redirected_to(conn)).query)["error"] == "access_denied"
    assert Repo.all(AgentConnection) == []
  end

  test "registration refuses an address the refused page can't name", %{team: team} do
    conn = register(team, %{"redirect_uris" => ["javascript:alert(1)"]})
    assert json_response(conn, 400)["error"] == "invalid_client_metadata"
  end

  test "token errors are OAuth errors, never cached", %{team: team} do
    conn =
      post(build_conn(), ~p"/teams/#{team}/oauth/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => "x"
      })

    assert json_response(conn, 400)["error"] == "invalid_grant"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "a team with Agents off has no metadata, registration, or tokens", ctx do
    {:ok, team} = SetTeamMCP.call(ctx.team, false, ctx.admin)

    assert build_conn()
           |> get("/.well-known/oauth-protected-resource/teams/#{team.subdomain}/mcp")
           |> json_response(404)

    assert build_conn()
           |> get("/.well-known/oauth-authorization-server/teams/#{team.subdomain}")
           |> json_response(404)

    assert team |> register(%{"redirect_uris" => [@claude]}) |> json_response(404)
    assert build_conn() |> post(~p"/teams/#{team}/oauth/token", %{}) |> json_response(404)
  end

  test "the JSON endpoints answer a browser's preflight", %{team: team} do
    conn =
      build_conn()
      |> put_req_header("origin", "http://localhost:6274")
      |> options("/teams/#{team.subdomain}/oauth/token")

    assert response(conn, 204)
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert [headers] = get_resp_header(conn, "access-control-allow-headers")
    assert headers =~ "content-type"

    conn = get(build_conn(), "/.well-known/oauth-authorization-server/teams/#{team.subdomain}")
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end
end
