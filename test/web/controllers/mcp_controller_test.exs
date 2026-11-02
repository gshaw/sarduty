defmodule Web.MCPControllerTest do
  # The MCP endpoint (#28): who gets in, which team they read, and what they never see.
  # Agents get in with an OAuth access token (#761); Web.OAuthControllerTest covers how.
  use Web.ConnCase

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.MCP.Tools
  alias App.Model.AgentConnection
  alias App.Model.MCPCall
  alias App.Model.Member
  alias App.Operation.DisconnectAgent
  alias App.Operation.SetTeamMCP
  alias App.Repo

  setup do
    admin = make_admin(AccountsFixtures.user_fixture())
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, team} = SetTeamMCP.call(team, true, admin)

    %{tokens: tokens, connection: record} = agent_connection_fixture(team, user)

    %{admin: admin, user: user, team: team, token: tokens["access_token"], record: record}
  end

  defp rpc(conn, token, subdomain, method, params \\ %{}) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> post(~p"/teams/#{subdomain}/mcp", %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" => params
    })
  end

  defp call_tool(conn, token, team, name, args \\ %{}) do
    conn = rpc(conn, token, team.subdomain, "tools/call", %{"name" => name, "arguments" => args})
    %{"result" => %{"content" => [%{"text" => text}]} = result} = json_response(conn, 200)
    {result, text}
  end

  describe "who gets in" do
    test "a live token reads its own team", %{conn: conn, team: team, token: token} do
      {result, text} = call_tool(conn, token, team, "report_fields")
      refute result["isError"]
      assert Jason.decode!(text)["team"] == team.name
      assert Jason.decode!(text)["hours_tags"]["primary"] == "Primary Hours"
    end

    test "a token for team A gets nothing from team B", ctx do
      other = team_fixture()
      group_fixture(other, %{title: "Other Team Group"})

      for method <- ["initialize", "tools/list", "tools/call"] do
        conn = rpc(build_conn(), ctx.token, other.subdomain, method, %{"name" => "report_fields"})
        assert json_response(conn, 404)
        refute conn.resp_body =~ "Other Team Group"
      end
    end

    test "a token never reads another team's names or reports", ctx do
      %{conn: conn, team: team, token: token} = ctx
      other = team_fixture()
      group_fixture(other, %{title: "Their Group"})
      qualification_fixture(other, %{title: "Their Qualification"})
      tag_fixture(other, "Their Tag")
      saved_report_fixture(other, "Their Report")

      for {name, args} <- tool_calls() do
        {_result, text} = call_tool(conn, token, team, name, args)

        for theirs <- ["Their Group", "Their Qualification", "Their Tag", "Their Report"],
            do: refute(text =~ theirs, "#{name} returned #{theirs}")
      end
    end

    test "no token, a wrong token, or a token in the query string gets 401", ctx do
      %{team: team, token: token} = ctx

      assert build_conn() |> post(~p"/teams/#{team}/mcp", %{}) |> json_response(401)
      conn = rpc(build_conn(), "sarduty_at_wrong", team.subdomain, "ping")
      assert json_response(conn, 401)

      conn = post(build_conn(), ~p"/teams/#{team}/mcp?access=#{token}", %{})
      assert json_response(conn, 401)
    end

    test "a 401 points the agent to the team's OAuth metadata", %{team: team} do
      metadata =
        "http://www.example.com:4002/.well-known/oauth-protected-resource/teams/#{team.subdomain}/mcp"

      conn = post(build_conn(), ~p"/teams/#{team}/mcp", %{})

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer resource_metadata="#{metadata}")
             ]

      assert json_response(conn, 401)["error"] =~ "Team settings, then Agents"

      conn = rpc(build_conn(), "sarduty_at_wrong", team.subdomain, "ping")

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer error="invalid_token", resource_metadata="#{metadata}")
             ]
    end

    test "an expired access token gets 401", %{conn: conn, team: team} = ctx do
      ctx.record |> Ecto.Changeset.change(access_expires_at: DateTime.utc_now()) |> Repo.update!()
      conn = rpc(conn, ctx.token, team.subdomain, "ping")
      assert json_response(conn, 401)
    end

    test "a disconnected agent gets 401", %{conn: conn, team: team, user: user} = ctx do
      {:ok, _} = DisconnectAgent.call(team, ctx.record.id, user)
      conn = rpc(conn, ctx.token, team.subdomain, "ping")
      assert json_response(conn, 401)
    end

    test "an agent on a team with Agents off gets 401, and stays out when it's on again",
         ctx do
      %{conn: conn, team: team, token: token, admin: admin} = ctx

      {:ok, team} = SetTeamMCP.call(team, false, admin)
      conn = rpc(conn, token, team.subdomain, "ping")
      assert json_response(conn, 401)
      assert Repo.reload!(ctx.record).revoked_at

      {:ok, team} = SetTeamMCP.call(team, true, admin)
      conn = rpc(build_conn(), token, team.subdomain, "ping")
      assert json_response(conn, 401)
    end

    test "a user who no longer passes the D4H bar gets 401", ctx do
      %{conn: conn, team: team, token: token, user: user} = ctx
      manager = Repo.get_by!(Member, team_id: team.id, email: user.email)
      Member.update!(manager, %{d4h_permission: 2})

      conn = rpc(conn, token, team.subdomain, "ping")

      assert json_response(conn, 401)
    end

    test "a user who left the team gets 401", ctx do
      %{conn: conn, team: team, token: token, user: user} = ctx
      manager = Repo.get_by!(Member, team_id: team.id, email: user.email)
      Member.update!(manager, %{left_at: ~U[2026-01-01 00:00:00Z]})

      conn = rpc(conn, token, team.subdomain, "ping")

      assert json_response(conn, 401)
    end

    test "a request from another site's page gets 403", %{conn: conn, team: team} = ctx do
      conn = put_req_header(conn, "origin", "https://evil.example")
      conn = rpc(conn, ctx.token, team.subdomain, "ping")
      assert json_response(conn, 403)
    end

    test "records when the agent was last used", %{conn: conn, team: team} = ctx do
      rpc(conn, ctx.token, team.subdomain, "ping")
      assert Repo.reload!(ctx.record).last_used_at
    end
  end

  describe "what tools return" do
    # The guard rail that lets a team say yes to agents (#816): no tool returns a member,
    # an activity, a row, or a count from the team's records.
    test "no tool response holds a record, a count, or a field outside its allowlist", ctx do
      %{conn: conn, team: team, token: token} = ctx

      member =
        member_fixture(team, %{
          name: "Pat Example",
          ref_id: "4471",
          email: "pat.secret@example.com",
          phone: "604-555-0199",
          address: "42 Hidden Road"
        })

      group_member_fixture(group_fixture(team, %{title: "Callout"}), member)
      qualification_award_fixture(qualification_fixture(team, %{title: "First Aid"}), member)

      activity =
        activity_fixture(team, %{
          title: "Search for the lost hiker",
          started_at: ~U[2026-03-01 17:00:00Z],
          finished_at: ~U[2026-03-01 20:00:00Z],
          address: "99 Trailhead Way",
          coordinate: "49.31234,-123.04567",
          description: "Meet at the gate",
          tracking_number: "PROS-2026-99881"
        })

      attendance_fixture(activity, member, %{
        started_at: ~U[2026-03-01 17:00:00Z],
        finished_at: ~U[2026-03-01 20:00:00Z]
      })

      tax_credit_letter_fixture(member, %{letter_content: "Dear Pat, private letter text"})
      # A list saved while searching for a member keeps the search in its values.
      saved_report_fixture(team, "Callout list", %{"q" => "4471"})

      secrets = [
        "Pat Example",
        "4471",
        "pat.secret@example.com",
        "604-555-0199",
        "42 Hidden Road",
        "Search for the lost hiker",
        "99 Trailhead Way",
        "49.31234",
        "Meet at the gate",
        "PROS-2026-99881",
        "private letter text",
        team.mailing_address
      ]

      for {name, args} <- tool_calls() do
        {result, text} = call_tool(conn, token, team, name, args)
        refute result["isError"], name
        output = Jason.decode!(text)
        allowed = Tools.find(name).fields()

        for key <- keys(output) do
          assert key in allowed, "#{name} returned #{key}, which is not in its fields/0"
        end

        for secret <- secrets, do: refute(text =~ secret, "#{name} returned #{secret}")
      end

      {_result, text} = call_tool(conn, token, team, "report_fields")
      names = Jason.decode!(text)
      assert names["groups"] == ["Callout"]
      assert names["qualifications"] == ["First Aid"]

      {_result, text} = call_tool(conn, token, team, "list_reports")
      assert Enum.any?(Jason.decode!(text)["reports"], &(&1["name"] == "Callout list"))
    end

    test "check_report checks without running, and links to New report", ctx do
      %{conn: conn, team: team, token: token} = ctx
      member_fixture(team, %{name: "Pat Example"})

      {result, text} =
        call_tool(conn, token, team, "check_report", %{
          "query" => "select name, last_attended from members",
          "name" => "Last seen"
        })

      refute result["isError"]
      output = Jason.decode!(text)
      assert output["columns"] == ["Member", "Last attended"]
      refute text =~ "Pat Example"

      %URI{path: path, query: query} = URI.parse(output["link"])
      assert path == "/teams/#{team.subdomain}/reports/new"

      assert URI.decode_query(query) == %{
               "query" => "select name, last_attended from members",
               "name" => "Last seen",
               "agent" => "Laptop agent"
             }
    end

    test "try_report runs on Coast Range SAR, never the team's records", ctx do
      %{conn: conn, team: team, token: token} = ctx
      member_fixture(team, %{name: "Pat Example"})

      {result, text} =
        call_tool(conn, token, team, "try_report", %{
          "query" => "select name, standing from members where name = 'Cameron Ruiz'"
        })

      refute result["isError"]
      output = Jason.decode!(text)
      assert output["team"] == "Coast Range SAR"
      assert output["made_up"]
      assert output["columns"] == ["Member", "Standing"]
      assert [["Cameron Ruiz", _standing]] = output["rows"]
      assert "Search manager" in output["names"]["qualifications"]
      assert "Rope team" in output["names"]["groups"]
      assert "Swiftwater" in output["names"]["tags"]
      refute text =~ "Pat Example"

      # A year sent as a JSON number picks that year, not this one.
      {_result, text} =
        call_tool(conn, token, team, "try_report", %{
          "query" => "select title from activities where year(started_at) = :year",
          "values" => %{"year" => 1999}
        })

      assert Jason.decode!(text)["rows"] == []

      {result, text} =
        call_tool(conn, token, team, "try_report", %{"query" => "select nme from members"})

      assert result["isError"]
      assert text =~ "members has no field nme"
    end

    test "check_report links a saved report to Change report", ctx do
      %{conn: conn, team: team, token: token} = ctx
      saved = saved_report_fixture(team, "Callout list")

      {_result, text} =
        call_tool(conn, token, team, "check_report", %{
          "query" => "select name from members",
          "report_id" => saved.id
        })

      assert URI.parse(Jason.decode!(text)["link"]).path ==
               "/teams/#{team.subdomain}/reports/#{saved.id}/edit"
    end

    test "check_report says what to fix", %{conn: conn, team: team} = ctx do
      for {args, message} <- [
            {%{"query" => "select nme from members"}, "members has no field nme"},
            {%{}, "Give query as the report's text."},
            {%{"query" => "select name from members", "report_id" => "1"},
             "Give report_id as a number."},
            {%{"query" => "select name from members", "report_id" => 999_999},
             "There is no saved report 999999."}
          ] do
        {result, text} = call_tool(conn, ctx.token, team, "check_report", args)
        assert result["isError"], inspect(args)
        assert text =~ message
      end
    end

    test "every call is logged with its tool, arguments, and items", ctx do
      %{conn: conn, team: team, token: token, user: user} = ctx
      args = %{"query" => "select name from members", "junk" => "x"}
      call_tool(conn, token, team, "check_report", args)

      [call] = Repo.all(MCPCall)
      assert call.team_id == team.id
      assert call.user_id == user.id
      assert call.tool == "check_report"
      assert call.arguments == %{"query" => "select name from members"}
      assert call.row_count == 0
    end
  end

  describe "the protocol" do
    test "initialize offers tools and agrees on a version", %{conn: conn, team: team} = ctx do
      conn =
        rpc(conn, ctx.token, team.subdomain, "initialize", %{"protocolVersion" => "2025-06-18"})

      result = json_response(conn, 200)["result"]
      assert result["protocolVersion"] == "2025-06-18"
      assert result["capabilities"]["tools"]

      conn =
        rpc(build_conn(), ctx.token, team.subdomain, "initialize", %{
          "protocolVersion" => "1999-01-01"
        })

      assert json_response(conn, 200)["result"]["protocolVersion"] == "2025-11-25"
    end

    test "tools/list lists the tools, every one read-only", ctx do
      conn = rpc(ctx.conn, ctx.token, ctx.team.subdomain, "tools/list")
      tools = json_response(conn, 200)["result"]["tools"]

      assert Enum.map(tools, & &1["name"]) ==
               ~w(report_fields list_reports try_report check_report)

      assert Enum.all?(tools, & &1["annotations"]["readOnlyHint"])
    end

    test "notifications/initialized gets 202 and no body", %{conn: conn, team: team} = ctx do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{ctx.token}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/teams/#{team}/mcp", %{
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized"
        })

      assert response(conn, 202) == ""
    end

    test "a batch is refused", %{conn: conn, team: team} = ctx do
      body = Jason.encode!([%{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"}])

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{ctx.token}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/teams/#{team}/mcp", body)

      assert json_response(conn, 400)["error"]["code"] == -32_600
    end

    test "an unknown tool or method is a JSON-RPC error", %{conn: conn, team: team} = ctx do
      conn = rpc(conn, ctx.token, team.subdomain, "tools/call", %{"name" => "send_email"})
      assert json_response(conn, 200)["error"]["code"] == -32_602

      conn = rpc(build_conn(), ctx.token, team.subdomain, "resources/list")
      assert json_response(conn, 200)["error"]["code"] == -32_601
    end

    test "GET is not allowed, since there is no event stream", %{conn: conn, team: team} = ctx do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{ctx.token}")
        |> get(~p"/teams/#{team}/mcp")

      assert response(conn, 405)
    end

    test "an unsupported protocol version header is refused", %{conn: conn, team: team} = ctx do
      conn = put_req_header(conn, "mcp-protocol-version", "1999-01-01")
      conn = rpc(conn, ctx.token, team.subdomain, "ping")
      assert json_response(conn, 400)
    end
  end

  test "tokens are stored hashed", %{token: token, record: record} do
    refute record.access_token_hash == token
    assert AgentConnection.hash(token) == record.access_token_hash
    refute AgentConnection |> Repo.all() |> Enum.any?(&(&1.access_token_hash == token))
  end

  # A query that reads members' names, activities' titles, and contact-free fields:
  # checking it must give back none of them.
  defp tool_calls do
    query = """
    select member, activity, activity.tracking_number, hours
    from attendance
    where status = 'Attended'
    """

    [
      {"report_fields", %{}},
      {"list_reports", %{}},
      {"try_report", %{"query" => query}},
      {"check_report", %{"query" => query, "name" => "Who went"}}
    ]
  end

  defp saved_report_fixture(team, name, values \\ %{}) do
    Repo.insert!(%App.Model.SavedReport{
      team_id: team.id,
      name: name,
      values: values,
      about: "Members of Callout",
      query: "select name from members where groups includes ('Callout')"
    })
  end

  # Every map key at any depth.
  defp keys(map) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> [key | keys(value)] end)

  defp keys(list) when is_list(list), do: Enum.flat_map(list, &keys/1)
  defp keys(_value), do: []
end
