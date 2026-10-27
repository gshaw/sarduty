defmodule Web.ActivityMileageLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "redirects when not authenticated", %{conn: conn} do
    team = team_fixture(%{subdomain: "alpha"})

    assert {:error, redirect} = live(conn, ~p"/teams/#{team}/activities/1/mileage")

    assert {:redirect, %{to: path, flash: flash}} = redirect
    assert path == ~p"/login"
    assert %{"error" => "Log in to see this page."} = flash
  end

  describe "when D4H refuses (#33)" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      activity = activity_fixture(team)
      %{conn: log_in_user(conn, user), team: team, activity: activity}
    end

    test "a refused key shows the reason, not a crash", ctx do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"title" => "Unauthorized"})
      end)

      {:ok, lv, _html} =
        live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/mileage")

      assert lv |> element("#load-error") |> render() =~ "D4H refused it: Unauthorized (401)"
      refute has_element?(lv, "button", "Generate mileage report")
    end

    test "an activity D4H has not got shows the reason in place of the report", ctx do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        if String.ends_with?(conn.request_path, "/exercises/#{ctx.activity.d4h_activity_id}"),
          do: conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"title" => "Not Found"}),
          else: Req.Test.json(conn, %{"id" => ctx.team.d4h_team_id, "title" => "Team"})
      end)

      {:ok, lv, _html} =
        live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/mileage")

      lv |> element("button", "Generate mileage report") |> render_click()
      render_async(lv)

      assert lv |> element("#report-error") |> render() =~ "D4H refused it: Not Found (404)"
      assert has_element?(lv, "button", "Generate mileage report")
    end
  end
end
