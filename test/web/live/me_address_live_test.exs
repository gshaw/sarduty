defmodule Web.MeAddressLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest
  import Web.OwnDetails

  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Repo

  setup :member_logged_in

  test "shows the member's copy, with no D4H read", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/address")

    assert has_element?(lv, "#details_address", "1 Main St")
    refute has_element?(lv, "#details_contact1_name")
  end

  test "saves the address straight to D4H as the member's change set",
       %{conn: conn, team: team, member: member, user: user} do
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/address")

    lv |> form("#address-form", details: %{address: "2 Oak Ave"}) |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me")

    path = "/v3/team/#{team.d4h_team_id}/members/#{member.d4h_member_id}"
    assert_received {:patch, ^path, body}
    assert body["deprecatedAddress"] == "2 Oak Ave"
    refute Map.has_key?(body, "primaryEmergencyContact")

    [change_set] = Repo.all(ChangeSet)
    assert {change_set.source, change_set.proposed_by_user_id} == {:member, user.id}
    [row] = Repo.all(ChangeSetRow)
    assert {row.status, row.member_id} == {:applied, member.id}
    assert row.new_value == %{"address" => "2 Oak Ave"}
    assert Repo.reload!(member).address == "2 Oak Ave"
  end

  test "an unchanged form sends nothing", %{conn: conn, team: team, member: member} do
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/address")

    lv |> form("#address-form") |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me")
    refute_received {:patch, _path, _body}
    assert Repo.all(ChangeSet) == []
  end

  test "a team admin page is still a 404 for the member", %{
    conn: conn,
    team: team,
    member: member
  } do
    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/members/#{member.id}/edit")
    end
  end
end
