defmodule Web.MemberGroupsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "a team admin's groups link to each group", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    group = group_fixture(team, %{title: "Callout"})
    group_member_fixture(group, member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/groups")

    assert has_element?(
             lv,
             ~s{#member_groups a[href="/teams/#{team.subdomain}/groups/#{group.id}"]}
           )
  end

  # Group pages stay with team admins (#440).
  test "a member sees the groups as plain text", %{conn: conn} do
    %{team: team, user: user} = member_with_login_fixture()
    other = member_fixture(team)
    group_member_fixture(group_fixture(team, %{title: "Callout"}), other)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{other.id}/groups")

    assert has_element?(lv, "#member_groups td", "Callout")
    refute has_element?(lv, "#member_groups a")
    refute has_element?(lv, "#member_groups button")
    refute has_element?(lv, "#add-group-form")
  end

  test "Remove on groups kept by hand, By its rules on the rest, and no add for members",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "key"}})
    organization_fixture([team], %{short_name: "BCSARA"})
    member = member_fixture(team)
    leavers = group_fixture(team, %{title: "Leavers"})
    callout = group_fixture(team, %{title: "Callout"})
    group_rule_fixture(callout, leavers)
    aircraft = group_fixture(team, %{title: "Aircraft", organization_owned: true})
    in_leavers = group_member_fixture(leavers, member)
    in_callout = group_member_fixture(callout, member)
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      send(test, {:d4h, conn.method, conn.request_path})
      Req.Test.json(conn, %{})
    end)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}/groups")

    assert has_element?(lv, "#remove-group-#{in_leavers.id}")
    refute has_element?(lv, "#remove-group-#{in_callout.id}")
    assert has_element?(lv, "#member_groups td", "By its rules")

    assert has_element?(
             lv,
             ~s{#add-group-id-select option[value="#{aircraft.id}"]},
             "Aircraft · BCSARA"
           )

    refute has_element?(lv, ~s{#add-group-id-select option[value="#{callout.id}"]})

    lv |> element("#remove-group-#{in_leavers.id}") |> render_click()
    assert_received {:d4h, "DELETE", _path}
    refute has_element?(lv, "#remove-group-#{in_leavers.id}")
    refute has_element?(lv, "#flash-info")
  end
end
