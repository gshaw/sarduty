defmodule Web.ActivityAttendanceLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.AttendanceScan

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = activity_fixture(team)
    %{conn: log_in_user(conn, user), user: user, team: team, activity: activity}
  end

  defp attendance_path(team, activity),
    do: ~p"/teams/#{team}/activities/#{activity.id}/attendance"

  defp scan!(team, activity, member, attrs \\ %{}) do
    %AttendanceScan{
      team_id: team.id,
      activity_id: activity.id,
      member_id: member.id,
      kind: "arrived",
      method: "name",
      scanned_at: DateTime.utc_now()
    }
    |> Map.merge(attrs)
    |> AttendanceScan.insert!()
  end

  test "the activity page links here", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}")
    assert has_element?(lv, ~s|a[href="#{attendance_path(team, activity)}"]|, "Send attendance")
  end

  test "Take attendance is under the title", %{conn: conn, team: team, activity: activity} do
    {:ok, lv, _html} = live(conn, attendance_path(team, activity))

    assert has_element?(
             lv,
             ~s|#take-attendance[href="/teams/#{team.subdomain}/activities/#{activity.id}/take-attendance"]|
           )
  end

  test "arrivals and departures show as they're recorded, with who recorded them", %{
    conn: conn,
    user: user,
    team: team,
    activity: activity
  } do
    member = member_fixture(team, %{name: "Raj Patel"})
    recorder = member_fixture(team, %{name: "Andrew Wallwork"})
    {:ok, lv, _html} = live(conn, attendance_path(team, activity))
    assert has_element?(lv, "#no-times")

    scan!(team, activity, member, %{
      recorded_by_user_id: user.id,
      recorded_by_member_id: recorder.id
    })

    assert render(lv) =~ "Raj Patel"
    assert has_element?(lv, "#times", "No departure scan")
    assert has_element?(lv, "#times", "Andrew Wallwork")
  end

  test "another team's activity is not found", %{conn: conn, team: team} do
    other = team_fixture() |> activity_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/activities/#{other.id}/attendance")
    end
  end

  test "yet to arrive lists who signed up, with Call and Text, and updates with each scan", %{
    conn: conn,
    team: team,
    activity: activity
  } do
    raj = member_fixture(team, %{name: "Raj Patel", phone: "604 555 1234"})
    attendance_fixture(activity, raj, %{status: "attending"})
    walk_in = member_fixture(team)

    {:ok, lv, _html} = live(conn, attendance_path(team, activity))
    assert has_element?(lv, "#yet-to-arrive-section", "1 of 1 signed up")
    assert has_element?(lv, "#yet-to-arrive-member-#{raj.id}", "604-555-1234")
    assert has_element?(lv, ~s|#yet-to-arrive-#{raj.id}-call[href="tel:+16045551234"]|)

    for member <- [raj, walk_in], do: scan!(team, activity, member)

    assert has_element?(lv, "#yet-to-arrive-none")

    assert has_element?(
             lv,
             "#yet-to-arrive-count",
             "2 members arrived, including 1 who did not sign up."
           )
  end
end
