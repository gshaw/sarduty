defmodule Web.Settings.TeamContactsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "a team admin picks one or two members, and goes back to General (#780, #1076)",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    sam = member_fixture(team, %{name: "Sam Rivera"})
    alex = member_fixture(team, %{name: "Alex Chen"})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = conn |> live(~p"/teams/#{team}/settings/contacts")

    lv
    |> form("#team-contacts-form",
      contacts: %{first_contact_id: sam.id, second_contact_id: sam.id}
    )
    |> render_submit()

    assert has_element?(lv, "#team-contacts-form", "Select someone else, or None.")

    {:ok, _lv, html} =
      lv
      |> form("#team-contacts-form",
        contacts: %{first_contact_id: sam.id, second_contact_id: alex.id}
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/settings")

    assert html =~ "Team contacts saved."
    team = App.Repo.reload!(team)
    assert {team.first_contact_id, team.second_contact_id} == {sam.id, alex.id}
  end
end
