defmodule Web.Settings.TeamLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  @secret "SECRET-TEAM-PAT-123"

  test "shows the team, with no form (#1076)", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{
        team: %{
          legal_name: "Coast Range Search and Rescue Society",
          abbreviated_name: "COAST",
          mailing_address: "123 Main St",
          lat: 49.2,
          lng: -123.1,
          timezone: "America/Vancouver"
        }
      })

    team
    |> Ecto.Changeset.change(city: "Cedar Creek BC", postal_code: "V5K 0A1")
    |> App.Repo.update!()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    assert has_element?(lv, "#team-head", team.name)
    assert has_element?(lv, "#team-initials")
    assert has_element?(lv, "#team-mailing-address", "Cedar Creek BC V5K 0A1")
    assert has_element?(lv, "#team-place", "49.20000, -123.10000")
    assert has_element?(lv, "#team-maps")
    assert has_element?(lv, "#team-timezone", "America/Vancouver")
    refute has_element?(lv, "#team_settings_form")

    assert has_element?(lv, ~s(#team-edit[href="/teams/#{team.subdomain}/settings/edit"]))
    assert has_element?(lv, "#team-d4h", "Open in D4H")
  end

  test "says where the records come from and whose key it is", %{conn: conn} do
    key = %{
      d4h_access_key: @secret,
      d4h_access_key_owner: "Alex Chen",
      d4h_access_key_member_id: 900,
      d4h_team_id: 4210,
      d4h_api_host: "api.ca.d4h.org"
    }

    %{user: user, team: team} = user_with_team_fixture(%{team: key})
    manager_fixture(team, %{name: "Alex Chen", d4h_member_id: 900, d4h_permission: 0})

    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    refute html =~ @secret
    assert has_element?(lv, "#team-records", "D4H, team 4210 in Canada")
    assert has_element?(lv, "#team-records", "Alex Chen's key, an Owner in D4H.")
  end

  test "Change team contacts and Change access key are actions", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    assert has_element?(
             lv,
             ~s(#team-contacts-change[href="/teams/#{team.subdomain}/settings/contacts"])
           )

    assert has_element?(
             lv,
             ~s(#team-key-change[href="/teams/#{team.subdomain}/settings/access-key"])
           )
  end

  test "names the organization", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    organization_fixture([team], %{name: "Coastal SAR Association", logo: nil})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    assert has_element?(lv, "#settings-organization", "Coastal SAR Association")
    assert has_element?(lv, "#settings-organization-logo", "CS")
  end

  test "404s for a team the user doesn't manage", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    other = team_fixture()

    assert_error_sent 404, fn ->
      conn |> log_in_user(user) |> get(~p"/teams/#{other}/settings")
    end
  end
end
