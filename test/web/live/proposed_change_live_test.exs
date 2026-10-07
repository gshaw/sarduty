defmodule Web.ProposedChangeLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Operation.ProposeAttendanceChanges

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = activity_fixture(team, %{title: "Rope rescue"})
    mei = member_fixture(team, %{name: "Mei Chen"})

    {:ok, change_set, []} =
      ProposeAttendanceChanges.call(
        team,
        user,
        activity.id,
        [%{"member_id" => mei.id, "status" => "attended", "reason" => "Sheet row 3"}],
        "Sign-in sheet for Rope rescue"
      )

    %{conn: log_in_user(conn, user), team: team, change_set: change_set}
  end

  test "lists sets waiting for review", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/proposed-changes")
    assert has_element?(lv, "#waiting-#{ctx.change_set.id}", "Sign-in sheet for Rope rescue")
  end

  test "shows each change with its reason, ticked", ctx do
    {:ok, lv, _html} =
      live(ctx.conn, ~p"/teams/#{ctx.team}/proposed-changes/#{ctx.change_set.id}")

    [row] = ctx.change_set.rows

    assert has_element?(lv, "#row-#{row.id}", "Mei Chen")
    assert has_element?(lv, "#row-#{row.id}", "Add as attended")
    assert has_element?(lv, "#row-#{row.id}", "Sheet row 3")
    assert has_element?(lv, "#select-#{row.id}[checked]")
  end

  test "discarding sends nothing", ctx do
    {:ok, lv, _html} =
      live(ctx.conn, ~p"/teams/#{ctx.team}/proposed-changes/#{ctx.change_set.id}")

    lv |> element("#discard") |> render_click()

    assert ChangeSet.count_waiting(ctx.team.id) == 0
  end
end
