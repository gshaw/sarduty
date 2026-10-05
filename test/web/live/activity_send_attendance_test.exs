defmodule Web.ActivitySendAttendanceTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Model.NoShow
  alias App.Model.Team
  alias App.Operation.CreateAttendanceLink
  alias App.Repo

  # The Send to D4H part of the Take attendance page, with D4H stubbed. Mei signed up
  # and arrived, Lena walked in, and Sam signed up and didn't come.
  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    activity = activity_fixture(team)
    mei = member_fixture(team, %{name: "Mei Chen"})
    lena = member_fixture(team, %{name: "Lena Park"})
    sam = member_fixture(team, %{name: "Sam Ortiz"})

    for member <- [mei, lena] do
      AttendanceScan.insert!(%AttendanceScan{
        team_id: team.id,
        activity_id: activity.id,
        member_id: member.id,
        kind: "arrived",
        method: "name",
        scanned_at: DateTime.utc_now()
      })
    end

    CreateAttendanceLink.call(team, activity, user, DateTime.utc_now())

    %{
      conn: log_in_user(conn, user),
      user: user,
      team: team,
      activity: activity,
      mei: mei,
      lena: lena,
      sam: sam
    }
  end

  defp row(ctx, id, member, status) do
    %{
      "id" => id,
      "activity" => %{"resourceType" => "Exercise", "id" => ctx.activity.d4h_activity_id},
      "member" => %{"resourceType" => "Member", "id" => member.d4h_member_id},
      "status" => status,
      "startsAt" => DateTime.to_iso8601(ctx.activity.started_at),
      "endsAt" => DateTime.to_iso8601(ctx.activity.finished_at),
      "duration" => 60
    }
  end

  # Answers reads like D4H and reports each write to the test.
  defp stub_d4h(ctx, published \\ false) do
    test_pid = self()
    rows = [row(ctx, 501, ctx.mei, "REQUESTED"), row(ctx, 503, ctx.sam, "REQUESTED")]

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")

      case {conn.method, path} do
        {"GET", "/exercises/" <> _} ->
          Req.Test.json(conn, %{"published" => published})

        {"GET", "/attendance"} ->
          Req.Test.json(conn, %{"results" => rows, "totalSize" => length(rows)})

        {method, path} ->
          json = Jason.decode!(body)
          send(test_pid, {:d4h_write, method, path, json})
          Req.Test.json(conn, written_row(ctx, json))
      end
    end)
  end

  defp written_row(ctx, json) do
    member = if json["memberId"] == ctx.lena.d4h_member_id, do: ctx.lena, else: ctx.mei
    row(ctx, 777, member, json["status"] || "ATTENDING")
  end

  defp open(ctx) do
    {:ok, lv, _html} =
      live(ctx.conn, ~p"/#{ctx.team.subdomain}/activities/#{ctx.activity.id}/take-attendance")

    Req.Test.allow(App.Adapter.D4H, self(), lv.pid)
    lv
  end

  test "review lists each change, and send makes them in D4H", ctx do
    stub_d4h(ctx)
    lv = open(ctx)

    lv |> element("#review") |> render_click()
    assert has_element?(lv, "#change-member-#{ctx.mei.id}", "Attended")
    assert has_element?(lv, "#change-member-#{ctx.lena.id}", "not signed up")
    assert has_element?(lv, "#change-member-#{ctx.sam.id}", "Absent")
    assert has_element?(lv, "#send", "Send 3 changes")

    lv |> form("#send-form") |> render_submit(%{"keys" => all_keys(ctx)})

    assert_received {:d4h_write, "PATCH", "/attendance/501", %{"status" => "ATTENDING"} = mei}
    assert mei["startsAt"] && mei["endsAt"]
    lena_id = ctx.lena.d4h_member_id
    assert_received {:d4h_write, "POST", "/attendance", %{"memberId" => ^lena_id}}
    assert_received {:d4h_write, "PATCH", "/attendance/503", %{"status" => "ABSENT"}}

    assert render(lv) =~ "3 attendance changes saved to D4H."
    refute AttendanceLink.find_current(ctx.team, ctx.activity)

    sam_id = ctx.sam.id
    assert [%NoShow{member_id: ^sam_id} = no_show] = NoShow.get_all(ctx.activity)
    assert has_element?(lv, "#no-show-#{no_show.id}", "Sam Ortiz")
  end

  test "a team admin marks a no-show followed up, and can undo it", ctx do
    no_show = NoShow.record!(ctx.activity, ctx.sam)
    lv = open(ctx)

    lv |> element("#follow-up-#{no_show.id}") |> render_click()
    assert Repo.reload(no_show).followed_up_at
    assert Repo.reload(no_show).followed_up_by_user_id == ctx.user.id
    assert has_element?(lv, "#follow-up-#{no_show.id}[checked]")

    lv |> element("#follow-up-#{no_show.id}") |> render_click()
    refute Repo.reload(no_show).followed_up_at
  end

  test "another team's no-show can't be changed", ctx do
    other_team = team_fixture()
    other_activity = activity_fixture(other_team)
    other = NoShow.record!(other_activity, member_fixture(other_team))
    lv = open(ctx)

    render_click(lv, "follow-up", %{"id" => other.id, "done" => "true"})
    refute Repo.reload(other).followed_up_at
  end

  test "sending twice records a no-show once", ctx do
    assert NoShow.record!(ctx.activity, ctx.sam)
    NoShow.record!(ctx.activity, ctx.sam)
    assert length(NoShow.get_all(ctx.activity)) == 1
  end

  test "an unchecked change is not sent", ctx do
    stub_d4h(ctx)
    lv = open(ctx)
    lv |> element("#review") |> render_click()

    keys = ["member-#{ctx.mei.id}"]
    lv |> form("#send-form") |> render_change(%{"keys" => keys})
    assert has_element?(lv, "#send", "Send 1 change")
    lv |> form("#send-form") |> render_submit(%{"keys" => keys})

    assert_received {:d4h_write, "PATCH", "/attendance/501", _}
    refute_received {:d4h_write, _, _, _}
  end

  test "a published activity can't be changed", ctx do
    stub_d4h(ctx, true)
    lv = open(ctx)
    lv |> element("#review") |> render_click()

    assert has_element?(lv, "#published", "Unpublish it in D4H first")
    refute has_element?(lv, "#send-form")
  end

  test "without a D4H access key, review says to save one", ctx do
    {:ok, _} = ctx.team.id |> Team.get!() |> Team.update(%{d4h_access_key: nil})
    lv = open(ctx)
    lv |> element("#review") |> render_click()
    assert render(lv) =~ "Save the team&#39;s D4H access key"
  end

  test "when D4H can't be read, nothing is sent", ctx do
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 500, ""))
    lv = open(ctx)
    lv |> element("#review") |> render_click()

    assert render(lv) =~ "D4H did not answer"
    refute has_element?(lv, "#send-form")
  end

  test "a refused write is listed, and the link stays open", ctx do
    stub_d4h(ctx)
    lv = open(ctx)
    lv |> element("#review") |> render_click()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")

      case {conn.method, path} do
        {"GET", "/exercises/" <> _} -> Req.Test.json(conn, %{"published" => false})
        {"GET", "/attendance"} -> Req.Test.json(conn, %{"results" => [], "totalSize" => 0})
        _ -> conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"title" => "Not allowed"})
      end
    end)

    lv |> form("#send-form") |> render_submit(%{"keys" => all_keys(ctx)})

    assert has_element?(lv, "#failures", "Mei Chen")
    assert has_element?(lv, "#failures", "Not allowed")
    assert render(lv) =~ "2 attendance changes did not go through."
    assert AttendanceLink.find_current(ctx.team, ctx.activity)
  end

  test "when D4H cannot find the activity, review says it may have been deleted", ctx do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"title" => "Not Found"})
    end)

    lv = open(ctx)
    lv |> element("#review") |> render_click()

    assert render(lv) =~
             "It may have been deleted or changed in D4H. D4H API error (404): Not Found"
  end

  test "a write D4H refuses with a 400 says the activity may have changed", ctx do
    stub_d4h(ctx)
    lv = open(ctx)
    lv |> element("#review") |> render_click()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      path = String.replace(conn.request_path, ~r{^/v3/team/\d+}, "")

      case {conn.method, path} do
        {"GET", "/exercises/" <> _} -> Req.Test.json(conn, %{"published" => false})
        {"GET", "/attendance"} -> Req.Test.json(conn, %{"results" => [], "totalSize" => 0})
        _ -> conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"title" => "Bad Request"})
      end
    end)

    lv |> form("#send-form") |> render_submit(%{"keys" => all_keys(ctx)})

    assert has_element?(
             lv,
             "#failures",
             "The activity may have been deleted or changed in D4H. D4H API error (400): Bad Request"
           )
  end

  defp all_keys(ctx), do: Enum.map([ctx.mei, ctx.lena, ctx.sam], &"member-#{&1.id}")
end
