defmodule Web.Settings.TeamAdminsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.TeamLoginGrant

  test "lists the team's managers and admin grants, not other members", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    editor = manager_fixture(team, %{name: "Eli Editor", d4h_permission: 1})
    _member = manager_fixture(team, %{name: "Mo Member", d4h_permission: 2})
    grant = TeamLoginGrant.grant!(team, "office@example.com", "role address")

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/team-admins")

    assert has_element?(lv, "#manager-#{editor.id}", "Editor")
    refute has_element?(lv, "#team-managers", "Mo Member")
    assert has_element?(lv, "#grant-#{grant.id}", "office@example.com")
  end

  test "lists a bot D4H made a team admin, with its badge", %{conn: conn} do
    key = %{d4h_access_key_member_id: 900, d4h_access_key_owner: "SAR Duty"}
    %{user: user, team: team} = user_with_team_fixture(%{team: key})
    sar_duty = manager_fixture(team, %{name: "SAR Duty", d4h_member_id: 900, not_a_person: true})
    person = manager_fixture(team, %{name: "Kim Lee"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/team-admins")

    assert has_element?(lv, "#manager-#{sar_duty.id}", "Not a person")
    assert has_element?(lv, "#manager-#{person.id}", "Kim Lee")
    refute has_element?(lv, "#manager-#{person.id}", "Not a person")
  end

  test "team contacts: a team admin picks one or two members (#780)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    sam = member_fixture(team, %{name: "Sam Rivera"})
    alex = member_fixture(team, %{name: "Alex Chen"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/team-admins")

    lv
    |> form("#team-contacts-form",
      contacts: %{first_contact_id: sam.id, second_contact_id: alex.id}
    )
    |> render_submit()

    assert render(lv) =~ "Saved team contacts."
    team = App.Repo.reload!(team)
    assert {team.first_contact_id, team.second_contact_id} == {sam.id, alex.id}

    lv
    |> form("#team-contacts-form",
      contacts: %{first_contact_id: sam.id, second_contact_id: sam.id}
    )
    |> render_submit()

    assert has_element?(lv, "#team-contacts-form", "Select someone else, or None.")
  end
end
