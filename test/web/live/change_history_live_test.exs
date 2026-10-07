defmodule Web.ChangeHistoryLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.D4HChange

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{name: "Jane Doe"})
    activity = activity_fixture(team, %{title: "Rope rescue"})

    D4HChange.insert!(%D4HChange{
      team_id: team.id,
      member_id: member.id,
      activity_id: activity.id,
      record_kind: :attendance,
      action: :changed,
      fields: ["status"],
      old_value: %{"status" => "absent"},
      new_value: %{"status" => "attending"},
      seen_after: ~U[2026-10-09 17:00:00.000000Z],
      seen_at: ~U[2026-10-09 17:10:00.000000Z]
    })

    %{conn: log_in_user(conn, user), team: team, member: member, activity: activity}
  end

  test "a member's history shows what changed in D4H", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/members/#{ctx.member.id}/history")

    assert has_element?(lv, "#member-history", "Rope rescue attendance changed: attended")
    assert has_element?(lv, "#member-history", "Oct 9, 10:00 to 10:10")
    assert has_element?(lv, "#member-history", "Someone in D4H")
  end

  test "an activity's history names the member", ctx do
    {:ok, lv, _html} =
      live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/history")

    assert has_element?(lv, "#activity-history", "Jane Doe attendance changed: attended")
  end
end
