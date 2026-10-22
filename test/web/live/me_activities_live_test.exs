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

  test "a coming sign-up is not on it and counts no hours (#364)",
       %{conn: conn, team: team, member: member, now: now} do
    next_week = DateTime.add(now, 7, :day)
    coming = activity_fixture(team, %{title: "Rope practice", started_at: next_week})

    attendance_fixture(coming, member, %{
      started_at: next_week,
      finished_at: DateTime.add(next_week, 3 * 3600)
    })

    {:ok, lv, html} = live(conn, ~p"/teams/#{team}/me/activities")

    refute html =~ "Rope practice"
    assert has_element?(lv, "#no-attendance")
    assert has_element?(lv, "#activity-count", "0 activities")
  end

  test "is titled for the year under Your membership, with this year's letter to come",
       %{conn: conn, team: team, year: year} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")

    assert has_element?(lv, "h1", "Your activities in #{year}")

    assert has_element?(
             lv,
             ~s{.breadcrumbs a[href="/teams/#{team.subdomain}/me"]},
             "Your membership"
           )

    assert has_element?(lv, "#letter", "Ready once a team admin makes it")
    assert has_element?(lv, "#missing", "Tell a team admin")
  end

  test "a past year shows its letter, its hours by kind, and each activity's hours",
       %{conn: conn, team: team, member: member, year: year} do
    started = (year - 1) |> Date.new!(6, 1) |> DateTime.new!(~T[18:00:00], "Etc/UTC")

    # A day apart, since the letter counts overlapping time once.
    for {{title, tags, hours}, day} <-
          Enum.with_index([
            {"Rope rescue", ["Primary Hours"], 6},
            {"PR booth", ["Secondary Hours"], 2},
            {"Board meeting", [], 3}
          ]) do
      started = DateTime.add(started, day, :day)
      activity = activity_fixture(team, %{title: title, tags: tags, started_at: started})

      attendance_fixture(activity, member, %{
        started_at: started,
        finished_at: DateTime.add(started, hours * 3600)
      })
    end

    letter =
      tax_credit_letter_fixture(member, %{
        year: year - 1,
        primary_minutes: 360,
        secondary_minutes: 120
      })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities?year=#{year - 1}")

    assert has_element?(lv, "#letter h2", "#{year - 1} tax credit letter")

    assert has_element?(
             lv,
             ~s{#letter-download[href="/teams/#{team.subdomain}/me/tax-credit-letters/#{letter.id}/pdf"]}
           )

    assert has_element?(lv, "#activity-count", "3 activities")
    assert has_element?(lv, "#hours-bars li", "Primary")
    assert has_element?(lv, "#hours-bars li", "6 hours")
    assert has_element?(lv, "#hours-bars li", "2 hours")
    assert has_element?(lv, "#hours-bars li", "3 hours")
    assert has_element?(lv, "#attendance tr", "Board meeting")
    assert has_element?(lv, "#attendance td", "Other")
  end

  test "a past year with no letter shows no letter",
       %{conn: conn, team: team, member: member, year: year} do
    started = (year - 1) |> Date.new!(6, 1) |> DateTime.new!(~T[18:00:00], "Etc/UTC")
    activity = activity_fixture(team, %{started_at: started})
    attendance_fixture(activity, member, %{started_at: started})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities?year=#{year - 1}")
    refute has_element?(lv, "#letter")
  end

  test "lists every year from this one back to the year the member joined",
       %{conn: conn, team: team, member: member, year: year} do
    joined = (year - 3) |> Date.new!(3, 1) |> DateTime.new!(~T[18:00:00], "Etc/UTC")
    member |> Ecto.Changeset.change(joined_at: joined) |> Repo.update!()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")

    for y <- year..(year - 3)//-1, do: assert(has_element?(lv, "#year-#{y}"))
    refute has_element?(lv, "#year-#{year - 4}")
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

  test "maps where the member went that year, and has no map without a place",
       %{conn: conn, team: team, member: member, mid_year: mid_year} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")
    refute has_element?(lv, "#where-you-went")

    activity =
      activity_fixture(team, %{
        title: "Rope rescue",
        coordinate: "49.335,-123.045",
        started_at: mid_year
      })

    attendance_fixture(activity, member, %{started_at: mid_year})
    elsewhere = activity_fixture(team, %{coordinate: "49.36,-123.02", started_at: mid_year})
    attendance_fixture(elsewhere, member_fixture(team), %{started_at: mid_year})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")
    assert has_element?(lv, "#where-you-went h2", "Where you went in")

    # One dot, for the activity the member attended.
    map = lv |> element("#year-map") |> render()
    assert map =~ "Rope rescue"
    assert map |> String.split("<circle") |> length() == 2
  end

  test "links each of the year's activities to D4H",
       %{conn: conn, team: team, member: member, mid_year: mid_year} do
    activity = activity_fixture(team, %{title: "Swiftwater exercise", started_at: mid_year})
    attendance = attendance_fixture(activity, member, %{started_at: mid_year})

    url = D4H.activity_url(team, activity)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/activities")

    assert has_element?(lv, ~s{#attendance-#{attendance.id} a[href="#{url}"]})
    refute has_element?(lv, ".table-group-row")
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
