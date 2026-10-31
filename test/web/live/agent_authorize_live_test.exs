defmodule Web.AgentAuthorizeLiveTest do
  # The Allow page (#761): what a team admin, a member, and anyone with an unknown agent
  # see, and the login on the way.
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Operation.RegisterAgentClient
  alias App.Operation.SetTeamMCP

  @claude "https://claude.ai/api/mcp/auth_callback"

  setup do
    admin = make_admin(AccountsFixtures.user_fixture())
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, team} = SetTeamMCP.call(team, true, admin)
    %{user: user, team: team, admin: admin}
  end

  defp authorize_path(team, redirect_uri, name \\ "Claude") do
    {:ok, client} =
      RegisterAgentClient.call(%{"client_name" => name, "redirect_uris" => [redirect_uri]})

    {_verifier, challenge} = pkce_fixture()

    query = %{
      "client_id" => client.client_id,
      "redirect_uri" => redirect_uri,
      "response_type" => "code",
      "code_challenge" => challenge,
      "code_challenge_method" => "S256",
      "state" => "st8"
    }

    "/teams/#{team.subdomain}/oauth/authorize?" <> URI.encode_query(query)
  end

  test "a team admin sees Allow, with the name from SAR Duty's list", ctx do
    path = authorize_path(ctx.team, @claude, "Not really Claude")
    {:ok, lv, _html} = live(log_in_user(build_conn(), ctx.user), path)

    assert has_element?(lv, "h1", "Connect an AI agent?")
    assert has_element?(lv, "#agent-name", "Claude")
    refute has_element?(lv, "#agent-name", "Not really")

    assert has_element?(
             lv,
             "#agent-warning",
             "Claude will see your members’ names, hours, and history."
           )

    assert has_element?(lv, "#agent-authorize-form input[name=state][value=st8]")
    assert has_element?(lv, "#agent-allow")
    assert has_element?(lv, "#agent-cancel")
  end

  test "an agent on the admin's computer names itself, escaped", ctx do
    path = authorize_path(ctx.team, "http://localhost:3000/cb", "<b>Claude Code</b>")
    {:ok, _lv, html} = live(log_in_user(build_conn(), ctx.user), path)

    assert html =~ "&lt;b&gt;Claude Code&lt;/b&gt;"
  end

  test "a member learns only team admins connect, with a way back", ctx do
    %{user: member, team: member_team} = member_with_login_fixture()
    {:ok, member_team} = SetTeamMCP.call(member_team, true, ctx.admin)

    {:ok, lv, _html} =
      live(log_in_user(build_conn(), member), authorize_path(member_team, @claude))

    assert has_element?(lv, "h1", "You cannot connect an agent")
    refute has_element?(lv, "#agent-allow")
    assert has_element?(lv, ~s{#agent-back[href^="#{@claude}?"]}, "Back to Claude")
  end

  test "a web agent not on the list is refused by its address", ctx do
    path = authorize_path(ctx.team, "https://agent.example.net/cb")
    {:ok, lv, _html} = live(log_in_user(build_conn(), ctx.user), path)

    assert has_element?(lv, "h1", "SAR Duty does not know this agent")
    assert has_element?(lv, "#agent-host", "agent.example.net")
    refute has_element?(lv, "#agent-allow")
  end

  test "an unknown client id is a link that does not work", ctx do
    {:ok, lv, _html} =
      live(
        log_in_user(build_conn(), ctx.user),
        "/teams/#{ctx.team.subdomain}/oauth/authorize?client_id=nope"
      )

    assert has_element?(lv, "h1", "This link does not work")
  end

  test "a known agent's bad request goes straight back to it", ctx do
    path = authorize_path(ctx.team, @claude) <> "&response_type=token"

    assert {:error, {:redirect, %{to: to}}} = live(log_in_user(build_conn(), ctx.user), path)
    assert URI.decode_query(URI.parse(to).query)["error"] == "unsupported_response_type"
  end

  test "is not found while the team has Agents off", ctx do
    path = authorize_path(ctx.team, @claude)
    {:ok, _team} = SetTeamMCP.call(ctx.team, false, ctx.admin)

    assert_raise Web.Status.NotFound, fn -> live(log_in_user(build_conn(), ctx.user), path) end
  end

  test "logged out, the login page says what it is for, and comes back after", ctx do
    path = authorize_path(ctx.team, @claude)
    conn = get(build_conn(), path)

    assert redirected_to(conn) == ~p"/login"
    assert get_session(conn, :user_return_to) == path
    refute Phoenix.Flash.get(conn.assigns.flash, :error)

    {:ok, lv, _html} = conn |> recycle() |> live(~p"/login")
    assert has_element?(lv, "#login-agent", "Log in to connect an AI agent to #{ctx.team.name}.")
  end
end
