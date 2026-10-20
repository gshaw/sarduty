defmodule Web.MeHoursLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  setup %{team: team}, do: this_year_fixture(team)

  test "shows this year's hours, and no one else's",
       %{conn: conn, team: team, member: member, mid_year: mid_year} do
    attended = activity_fixture(team, %{started_at: mid_year})
    finish = DateTime.add(mid_year, 2 * 3600)
    attendance_fixture(attended, member, %{started_at: mid_year, finished_at: finish})
    other = activity_fixture(team, %{started_at: mid_year})
    attendance_fixture(other, member_fixture(team), %{started_at: mid_year, finished_at: finish})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/hours")
    assert has_element?(lv, "#hours-primary", "2 hours")
    assert has_element?(lv, "#hours-total", "2 hours")
  end

  test "a year with no attendance is a 404", %{conn: conn, team: team} do
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/me/hours?year=1999") end
  end

  test "counts the organization's hours tags (#289)",
       %{conn: conn, team: team, member: member, mid_year: mid_year} do
    organization_fixture([team], %{
      primary_hours_tag: "SRVTC Primary Activity",
      secondary_hours_tag: "SRVTC Secondary Activity"
    })

    finish = DateTime.add(mid_year, 2 * 3600)
    tags = ["SRVTC Secondary Activity"]
    counted = activity_fixture(team, %{started_at: mid_year, tags: tags})
    attendance_fixture(counted, member, %{started_at: mid_year, finished_at: finish})
    # The default tag counts for nothing in this organization.
    uncounted = activity_fixture(team, %{started_at: mid_year, tags: ["Primary Hours"]})
    attendance_fixture(uncounted, member, %{started_at: mid_year, finished_at: finish})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/hours")

    assert has_element?(lv, "#hours-primary", "0 hours")
    assert has_element?(lv, "#hours-secondary", "2 hours")
    assert render(lv) =~ "SRVTC Primary Activity or SRVTC Secondary Activity tag"
  end
end
