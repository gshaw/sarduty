defmodule Web.MeEmergencyContactsLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest
  import Web.OwnDetails

  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.Repo

  setup :member_logged_in

  test "shows the member's copy, with no D4H read", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/emergency-contacts")

    assert has_element?(lv, "#details_contact1_name[value='Sam Rivera']")
    refute has_element?(lv, "#details_address")
  end

  test "saves a contact straight to D4H, whole, and nothing else",
       %{conn: conn, team: team, member: member} do
    stub_d4h(team, member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/emergency-contacts")

    lv
    |> form("#contacts-form", details: %{contact1_primary_phone: "604-555-0199"})
    |> render_submit()

    assert_redirect(lv, ~p"/teams/#{team}/me")

    assert_received {:patch, _path, body}
    assert body["primaryEmergencyContact"]["primaryPhone"] == "604-555-0199"
    assert body["primaryEmergencyContact"]["name"] == "Sam Rivera"
    refute Map.has_key?(body, "secondaryEmergencyContact")
    refute Map.has_key?(body, "deprecatedAddress")

    [row] = Repo.all(ChangeSetRow)
    assert Map.keys(row.new_value) == ["primary_emergency_contact"]
    member = Repo.reload!(member)
    assert member.primary_emergency_contact["primary_phone"] == "604-555-0199"
    assert member.address == "1 Main St"
  end

  test "a team on SAR Duty Records changes emergency contacts too", %{conn: conn, member: member} do
    team =
      member.team
      |> Ecto.Changeset.change(d4h_api_host: D4H.records_host())
      |> Repo.update!()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/emergency-contacts")

    assert has_element?(lv, "#details_contact1_name[value='Sam Rivera']")
  end
end
