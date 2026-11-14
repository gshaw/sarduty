defmodule Web.Settings.TeamFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team

  test "saves the team's three names, and goes back to General (#738, #1076)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = conn |> live(~p"/teams/#{team}/settings/edit")
    assert has_element?(lv, "#team-names-lead")
    refute has_element?(lv, "#form_timezone")

    names = %{
      name: "York Sunbury SAR",
      legal_name: "York Sunbury Search and Rescue Inc.",
      abbreviated_name: "YSSR"
    }

    {:ok, _lv, html} =
      lv
      |> form("#team_settings_form", form: names)
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/settings")

    assert html =~ "Team saved."

    assert %{
             name: "York Sunbury SAR",
             legal_name: "York Sunbury Search and Rescue Inc.",
             abbreviated_name: "YSSR"
           } = Team.get!(team.id)
  end

  # Facts about the team, which letters and forms print, beside its legal name (#995).
  test "saves the team's address, trimmed", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/edit")

    address = %{mailing_address: "PO Box 12", city: " Squamish BC ", postal_code: "V8B 0A1"}
    lv |> form("#team_settings_form", form: address) |> render_submit()

    assert %Team{mailing_address: "PO Box 12", city: "Squamish BC", postal_code: "V8B 0A1"} =
             Team.get!(team.id)
  end

  test "changes the team in the URL, not the one last opened", %{conn: conn} do
    %{user: user, team: first} = user_with_team_fixture()
    second = team_fixture(%{name: "Second SAR"})
    manager_fixture(second, %{email: user.email})
    App.Repo.update_all(App.Accounts.User, set: [last_team_id: first.id])

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{second}/settings/edit")

    lv |> form("#team_settings_form", form: %{name: "Renamed Second"}) |> render_submit()

    assert Team.get!(second.id).name == "Renamed Second"
    assert Team.get!(first.id).name == first.name
  end

  test "breadcrumbs go back to General, and Cancel saves nothing", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings/edit")

    assert has_element?(
             lv,
             ~s(.breadcrumbs a[href="/teams/#{team.subdomain}/settings"]),
             "General"
           )

    assert has_element?(lv, ~s(#team-cancel[href="/teams/#{team.subdomain}/settings"]))
  end
end
