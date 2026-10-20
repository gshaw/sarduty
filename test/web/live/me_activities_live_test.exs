defmodule Web.MeActivitiesLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Adapter.D4H
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  setup %{team: team}, do: this_year_fixture(team)

  test "shows this year's activities, and no one else's",
       %{conn: conn, team: team, member: member, mid_year: mid_year} do
    attended = activity_fixture(team, %{title: "Swiftwater exercise", started_at: mid_year})
    finish = DateTime.add(mid_year, 2 * 3600)

    attendance =
      attendance_fixture(attended, member, %{started_at: mid_year, finished_at: finish})

    other = activity_fixture(team, %{title: "Not mine", started_at: mid_year})
    other_attendance = attendance_fixture(other, member_fixture(team), %{started_at: mid_year})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")
    assert has_element?(lv, "#attendance-#{attendance.id}", "Swiftwater exercise")
    refute has_element?(lv, "#attendance-#{other_attendance.id}")
  end

  test "lists a sign-up for a coming activity apart, counting no hours for it (#364)",
       %{conn: conn, team: team, member: member, now: now} do
    next_week = DateTime.add(now, 7, :day)
    next_year = DateTime.add(now, 400, :day)
    coming = activity_fixture(team, %{title: "Rope practice", started_at: next_week})

    soon =
      attendance_fixture(coming, member, %{
        started_at: next_week,
        finished_at: DateTime.add(next_week, 3 * 3600)
      })

    later_activity =
      activity_fixture(team, %{title: "Next year's course", started_at: next_year})

    later = attendance_fixture(later_activity, member, %{started_at: next_year})

    {:ok, lv, html} = live(conn, ~p"/teams/#{team}/me/activities")

    assert has_element?(lv, "#signed-up-#{soon.id}", "Rope practice")
    assert has_element?(lv, "#signed-up-#{later.id}", "Next year's course")

    assert :binary.match(html, "signed-up-#{soon.id}") <
             :binary.match(html, "signed-up-#{later.id}")

    assert has_element?(lv, "#no-attendance")
    refute has_element?(lv, "#years")

    {:ok, hours, _html} = live(conn, ~p"/teams/#{team}/me/hours")
    assert has_element?(hours, "#hours-total", "0 hours")
  end

  test "switches to an earlier year the member attended in",
       %{conn: conn, team: team, member: member, year: year} do
    last_year = (year - 1) |> Date.new!(6, 1) |> DateTime.new!(~T[18:00:00], "Etc/UTC")
    activity = activity_fixture(team, %{title: "Last year's search", started_at: last_year})
    attendance = attendance_fixture(activity, member, %{started_at: last_year})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")
    assert has_element?(lv, "#no-attendance")

    lv |> element("#year-#{year - 1}") |> render_click()

    assert_patch(lv, ~p"/teams/#{team}/me/activities?year=#{year - 1}")
    assert has_element?(lv, "#attendance-#{attendance.id}", "Last year's search")
  end

  test "a year with no attendance, or not a year, is a 404", %{conn: conn, team: team} do
    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/me/activities?year=1999")
    end

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/me/activities?year=x")
    end
  end

  test "groups the year's activities by month, each linked to D4H",
       %{conn: conn, team: team, member: member, mid_year: mid_year} do
    activity = activity_fixture(team, %{title: "Swiftwater exercise", started_at: mid_year})
    attendance = attendance_fixture(activity, member, %{started_at: mid_year})

    month =
      mid_year
      |> DateTime.shift_zone!(team.timezone)
      |> DateTime.to_date()
      |> Date.beginning_of_month()
      |> Date.to_iso8601()

    url = D4H.activity_url(team, activity)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")

    assert has_element?(
             lv,
             ~s{#attendance-#{month} #attendance-#{attendance.id} a[href="#{url}"]}
           )
  end

  test "a team on SAR Duty Records has no activity links",
       %{conn: conn, team: team, member: member, mid_year: mid_year} do
    team
    |> Ecto.Changeset.change(d4h_api_host: D4H.records_host())
    |> Repo.update!()

    activity = activity_fixture(team, %{title: "Swiftwater exercise", started_at: mid_year})
    attendance = attendance_fixture(activity, member, %{started_at: mid_year})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")

    assert has_element?(lv, "#attendance-#{attendance.id}", "Swiftwater exercise")
    refute has_element?(lv, "#attendance-#{attendance.id} a")
  end
end
