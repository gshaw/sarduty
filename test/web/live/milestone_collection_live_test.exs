defmodule Web.MilestoneCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), team: team}
  end

  defp attend_incident(team, member, title, days_ago) do
    starts = DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(team, %{title: title, activity_kind: "incident", started_at: starts})

    attendance_fixture(activity, member, %{
      started_at: starts,
      finished_at: DateTime.add(starts, 3600)
    })
  end

  test "lists the last 90 days' milestones, and a member's over all time", %{
    conn: conn,
    team: team
  } do
    sam = member_fixture(team, %{name: "Sam Rivera", joined_at: ~U[2026-01-01 00:00:00Z]})
    alex = member_fixture(team, %{name: "Alex Chen", joined_at: ~U[2026-01-01 00:00:00Z]})
    attend_incident(team, sam, "Missing hiker", 10)
    attend_incident(team, alex, "Overdue skier", 200)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/milestones")
    assert has_element?(lv, "#milestones-#{sam.id}-incidents-1", "Missing hiker")
    refute has_element?(lv, "#milestones-#{alex.id}-incidents-1")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/milestones?member=#{alex.id}&when=all")
    assert has_element?(lv, "#milestones-#{alex.id}-incidents-1", "First incident")
    refute has_element?(lv, "#milestones-#{sam.id}-incidents-1")
  end

  test "leaves out members who left, and other teams'", %{conn: conn, team: team} do
    gone = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    attend_incident(team, gone, "Missing hiker", 400)
    other = team_fixture()
    attend_incident(other, member_fixture(other), "Elsewhere", 10)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/milestones?when=all")
    assert has_element?(lv, "#no-milestones")
  end

  test "the member sidebar shows the latest and links to the rest", %{conn: conn, team: team} do
    sam = member_fixture(team, %{joined_at: ~U[2024-01-01 00:00:00Z]})
    attend_incident(team, sam, "Missing hiker", 10)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{sam.id}")
    assert has_element?(lv, "#member-milestones", "First incident")

    assert has_element?(
             lv,
             ~s|#member-milestones-all[href="/teams/#{team.subdomain}/milestones?member=#{sam.id}&when=all"]|,
             "All 2 milestones"
           )

    nobody = member_fixture(team, %{joined_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{nobody.id}")
    assert has_element?(lv, "#member-milestones", "None")
  end
end
