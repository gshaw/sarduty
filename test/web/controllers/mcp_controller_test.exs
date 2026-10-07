defmodule Web.MCPControllerTest do
  # The MCP endpoint (#28): who gets in, which team they read, and what they never see.
  use Web.ConnCase

  import App.DataFixtures

  alias App.AccountsFixtures
  alias App.MCP.Tools
  alias App.Model.ChangeSet
  alias App.Model.D4HChange
  alias App.Model.MCPCall
  alias App.Model.MCPToken
  alias App.Model.Member
  alias App.Operation.CreateMCPToken
  alias App.Operation.RevokeMCPToken
  alias App.Operation.SetTeamMCP
  alias App.Repo

  setup do
    admin = make_admin(AccountsFixtures.user_fixture())
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, team} = SetTeamMCP.call(team, true, admin)

    {:ok, token, record} =
      CreateMCPToken.call(team, user, %{"name" => "Laptop", "no_training" => "true"})

    %{admin: admin, user: user, team: team, token: token, record: record}
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
      {result, text} = call_tool(conn, token, team, "get_team")
      refute result["isError"]
      assert Jason.decode!(text)["name"] == team.name
    end

    test "a token for team A gets nothing from team B", ctx do
      other = team_fixture()
      member_fixture(other, %{name: "Other Team Member"})

      for method <- ["initialize", "tools/list", "tools/call"] do
        conn = rpc(build_conn(), ctx.token, other.subdomain, method, %{"name" => "list_members"})
        assert json_response(conn, 404)
        refute conn.resp_body =~ "Other Team Member"
      end
    end

    test "a token never reads another team's rows, even through joins", ctx do
      %{conn: conn, team: team, token: token} = ctx
      other = team_fixture()
      theirs = member_fixture(other, %{name: "Other Team Member"})
      group_member_fixture(group_fixture(team), theirs)
      activity = activity_fixture(team, %{started_at: ~U[2026-03-01 17:00:00Z]})
      attendance_fixture(activity, theirs, %{started_at: ~U[2026-03-01 17:00:00Z]})
      qualification_award_fixture(qualification_fixture(team), theirs)
      activity_fixture(other, %{title: "Their Activity", started_at: ~U[2026-03-01 17:00:00Z]})

      for {name, args} <- tool_calls() do
        {_result, text} = call_tool(conn, token, team, name, args)
        refute text =~ "Other Team Member", name
        refute text =~ "Their Activity", name
      end
    end

    test "no token, a wrong token, or a token in the query string gets 401", ctx do
      %{team: team, token: token} = ctx

      assert build_conn() |> post(~p"/teams/#{team}/mcp", %{}) |> json_response(401)
      conn = rpc(build_conn(), "sarduty_mcp_wrong", team.subdomain, "ping")
      assert json_response(conn, 401)

      conn = post(build_conn(), ~p"/teams/#{team}/mcp?access=#{token}", %{})
      assert json_response(conn, 401)
      assert get_resp_header(conn, "www-authenticate") != []
    end

    test "a revoked token gets 401", %{conn: conn, team: team, user: user} = ctx do
      {:ok, _} = RevokeMCPToken.call(team, ctx.record.id, user)
      conn = rpc(conn, ctx.token, team.subdomain, "ping")
      assert json_response(conn, 401)
    end

    test "a token on a team with MCP off gets 401, and stays revoked when it's on again",
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

    test "records when the token was last used", %{conn: conn, team: team} = ctx do
      rpc(conn, ctx.token, team.subdomain, "ping")
      assert Repo.reload!(ctx.record).last_used_at
    end
  end

  describe "what tools return" do
    test "no tool response holds a field outside its allowlist, or contact details", ctx do
      %{conn: conn, team: team, token: token} = ctx

      member =
        member_fixture(team, %{
          name: "Pat Example",
          email: "pat.secret@example.com",
          phone: "604-555-0199",
          address: "42 Hidden Road"
        })

      group_member_fixture(group_fixture(team, %{title: "MIT"}), member)

      activity =
        activity_fixture(team, %{
          started_at: ~U[2026-03-01 17:00:00Z],
          finished_at: ~U[2026-03-01 20:00:00Z],
          address: "99 Trailhead Way",
          coordinate: "49.31234,-123.04567",
          description: "Meet at the gate"
        })

      attendance_fixture(activity, member, %{
        started_at: ~U[2026-03-01 17:00:00Z],
        finished_at: ~U[2026-03-01 20:00:00Z]
      })

      qualification_award_fixture(qualification_fixture(team, %{title: "First Aid"}), member)
      tax_credit_letter_fixture(member, %{letter_content: "Dear Pat, private letter text"})

      secrets = [
        "pat.secret@example.com",
        "604-555-0199",
        "42 Hidden Road",
        "99 Trailhead Way",
        "49.31234",
        "Meet at the gate",
        "private letter text",
        team.mailing_address
      ]

      D4HChange.insert!(%D4HChange{
        team_id: team.id,
        member_id: member.id,
        record_kind: :member,
        action: :changed,
        fields: ["email", "phone"],
        old_value: %{},
        new_value: %{},
        seen_at: ~U[2026-03-02 17:00:00.000000Z]
      })

      history_calls = [
        {"member_history", %{"member_id" => member.id}},
        {"activity_history", %{"activity_id" => activity.id}}
      ]

      for {name, args} <- tool_calls() ++ history_calls do
        {result, text} = call_tool(conn, token, team, name, args)
        refute result["isError"], name
        output = Jason.decode!(text)
        allowed = Tools.find(name).fields()

        for key <- keys(output) do
          assert key in allowed, "#{name} returned #{key}, which is not in its fields/0"
        end

        for key <- ~w(email phone address coordinate lat lng description letter_content),
            do: refute(key in keys(output), "#{name} returned #{key}")

        for secret <- secrets, do: refute(text =~ secret, "#{name} returned #{secret}")
      end
    end

    test "attendance_summary gives hours per tag and kind", ctx do
      %{conn: conn, team: team, token: token} = ctx
      member = member_fixture(team, %{name: "Pat Example"})

      activity =
        activity_fixture(team, %{
          started_at: ~U[2026-03-01 17:00:00Z],
          finished_at: ~U[2026-03-01 20:00:00Z],
          tags: ["Primary Hours", "Rope"]
        })

      attendance_fixture(activity, member, %{
        started_at: ~U[2026-03-01 17:00:00Z],
        finished_at: ~U[2026-03-01 19:30:00Z]
      })

      {_result, text} =
        call_tool(conn, token, team, "attendance_summary", %{
          "from" => "2026-01-01",
          "to" => "2026-03-31"
        })

      pat = Enum.find(Jason.decode!(text)["members"], &(&1["name"] == "Pat Example"))
      assert pat["total_hours"] == 2.5
      assert pat["activities"] == 1

      assert pat["by_tag"] == [
               %{
                 "tag" => "Primary Hours",
                 "activity_kind" => "exercise",
                 "hours" => 2.5,
                 "activities" => 1
               },
               %{
                 "tag" => "Rope",
                 "activity_kind" => "exercise",
                 "hours" => 2.5,
                 "activities" => 1
               }
             ]
    end

    test "a tool given bad arguments says what to fix", %{conn: conn, team: team} = ctx do
      {result, text} = call_tool(conn, ctx.token, team, "list_activities", %{"from" => "soon"})
      assert result["isError"]
      assert text =~ "Give from as a date"
    end

    test "every call is logged with its tool, arguments, and rows", ctx do
      %{conn: conn, team: team, token: token, user: user} = ctx
      args = %{"from" => "2026-01-01", "to" => "2026-01-31", "tag" => "Rope", "junk" => "x"}
      call_tool(conn, token, team, "list_activities", args)

      [call] = Repo.all(MCPCall)
      assert call.team_id == team.id
      assert call.user_id == user.id
      assert call.tool == "list_activities"
      assert call.arguments == %{"from" => "2026-01-01", "to" => "2026-01-31", "tag" => "Rope"}
      assert call.row_count == 0
    end
  end

  describe "proposing changes" do
    test "saves a proposal for a team admin and never calls D4H", ctx do
      activity = activity_fixture(ctx.team, %{title: "Rope rescue"})
      member = member_fixture(ctx.team, %{name: "Mei Chen"})

      # No Req.Test stub: a call to D4H would fail the test.
      {result, text} =
        call_tool(ctx.conn, ctx.token, ctx.team, "propose_attendance_changes", %{
          "activity_id" => activity.id,
          "summary" => "Sign-in sheet",
          "changes" => [
            %{"member_id" => member.id, "status" => "attended", "reason" => "Row 1"},
            %{"member_id" => 999_999, "status" => "attended"}
          ]
        })

      refute result["isError"]
      output = Jason.decode!(text)
      assert output["proposed"] == 1
      assert output["left_out"] == ["No member 999999 on this team."]
      assert output["review_url"] =~ "/teams/#{ctx.team.subdomain}/proposed-changes/"

      [change_set] = ChangeSet.get_waiting(ctx.team.id)
      assert change_set.source == :agent
      assert change_set.proposed_by_user_id == ctx.user.id
      assert change_set.applied_at == nil
    end

    test "can't propose for another team's activity", ctx do
      other = activity_fixture(team_fixture())

      {result, text} =
        call_tool(ctx.conn, ctx.token, ctx.team, "propose_attendance_changes", %{
          "activity_id" => other.id,
          "summary" => "x",
          "changes" => [%{"member_id" => 1, "status" => "attended"}]
        })

      assert result["isError"]
      assert text =~ "No activity #{other.id} on this team."
      assert ChangeSet.count_waiting(ctx.team.id) == 0
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

    test "tools/list lists the tools, and marks the one that proposes", ctx do
      conn = rpc(ctx.conn, ctx.token, ctx.team.subdomain, "tools/list")
      tools = json_response(conn, 200)["result"]["tools"]

      assert Enum.map(tools, & &1["name"]) ==
               ~w(get_team list_members attendance_summary list_activities list_qualifications
                  member_history activity_history propose_attendance_changes)

      read_only = for t <- tools, t["annotations"]["readOnlyHint"], do: t["name"]
      refute "propose_attendance_changes" in read_only
      assert length(read_only) == 7
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
    refute record.token_hash == token
    assert MCPToken.hash(token) == record.token_hash
    refute MCPToken |> Repo.all() |> Enum.any?(&(&1.token_hash == token))
  end

  defp tool_calls do
    range = %{"from" => "2026-01-01", "to" => "2026-12-31"}

    [
      {"get_team", %{}},
      {"list_members", %{}},
      {"attendance_summary", range},
      {"list_activities", range},
      {"list_qualifications", %{}}
    ]
  end

  # Every map key at any depth.
  defp keys(map) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> [key | keys(value)] end)

  defp keys(list) when is_list(list), do: Enum.flat_map(list, &keys/1)
  defp keys(_value), do: []
end
