defmodule Web.ActivityTakeAttendanceLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Model.ShortLink
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = activity_fixture(team)
    %{conn: log_in_user(conn, user), team: team, activity: activity}
  end

  defp take_path(team, activity),
    do: ~p"/teams/#{team}/activities/#{activity.id}/take-attendance"

  test "the activity page links here", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
    assert has_element?(lv, ~s|a[href="#{take_path(team, activity)}"]|, "Take attendance")
  end

  test "a team admin makes a link, then closes it", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, take_path(team, activity))
    assert has_element?(lv, "#no-link")

    lv |> element("#no-link #create-link") |> render_click()
    link = AttendanceLink.find_current(team, activity)
    assert has_element?(lv, ~s|#attendance-link-url[href$="/s/#{link.short_link.code}"]|)
    assert has_element?(lv, ~s|#share-link[hidden][data-url$="/s/#{link.short_link.code}"]|)
    assert has_element?(lv, "#copy-status[role=status]")

    lv |> element("#close-link") |> render_click()
    assert has_element?(lv, "#no-link")
    assert Repo.reload(link).closed_at
    refute Repo.get(ShortLink, link.short_link_id)
  end

  test "a new link closes the old one", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, take_path(team, activity))
    lv |> element("#no-link #create-link") |> render_click()
    first = AttendanceLink.find_current(team, activity)

    lv |> element("#open-link #create-link") |> render_click()
    assert Repo.reload(first).closed_at
    refute Repo.get(ShortLink, first.short_link_id)
    refute AttendanceLink.find_current(team, activity).id == first.id
  end

  test "arrivals and departures show as the door records them", %{
    conn: conn,
    team: team,
    activity: activity
  } do
    member = member_fixture(team, %{name: "Raj Patel"})
    {:ok, lv, _html} = live(conn, take_path(team, activity))
    assert has_element?(lv, "#no-times")

    AttendanceScan.insert!(%AttendanceScan{
      team_id: team.id,
      activity_id: activity.id,
      member_id: member.id,
      kind: "arrived",
      method: "name",
      scanned_at: DateTime.utc_now()
    })

    assert render(lv) =~ "Raj Patel"
    assert has_element?(lv, "#times", "No departure scan")
  end

  test "another team's activity is not found", %{conn: conn, team: team} do
    other = team_fixture() |> activity_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/activities/#{other.id}/take-attendance")
    end
  end

  test "yet to arrive lists who signed up and updates as the door records them", %{
    conn: conn,
    team: team,
    activity: activity
  } do
    raj = member_fixture(team, %{name: "Raj Patel"})
    attendance_fixture(activity, raj, %{status: "attending"})
    walk_in = member_fixture(team)

    {:ok, lv, _html} = live(conn, take_path(team, activity))
    assert has_element?(lv, "#yet-to-arrive-section", "1 of 1 signed up")
    assert has_element?(lv, "#yet-to-arrive-member-#{raj.id}")

    for member <- [raj, walk_in] do
      AttendanceScan.insert!(%AttendanceScan{
        team_id: team.id,
        activity_id: activity.id,
        member_id: member.id,
        kind: "arrived",
        method: "name",
        scanned_at: DateTime.utc_now()
      })
    end

    assert has_element?(lv, "#yet-to-arrive-none")

    assert has_element?(
             lv,
             "#yet-to-arrive-count",
             "2 members arrived, including 1 who did not sign up."
           )
  end
end
