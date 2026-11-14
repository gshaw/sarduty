defmodule Web.Settings.TeamLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team

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
    assert has_element?(lv, "#team-head-facts", "Coast Range Search and Rescue Society · COAST")
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

  test "team contacts, with Change team contacts", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")
    assert has_element?(lv, "#team-contacts", "None yet. Get help lists no one.")

    sam = member_fixture(team, %{name: "Sam Rivera", email: "sam@example.com"})
    team |> Ecto.Changeset.change(first_contact_id: sam.id) |> App.Repo.update!()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")
    assert has_element?(lv, "#team-contact-#{sam.id}", "sam@example.com")
    assert has_element?(lv, "#team-contacts", "Get help lists them for members.")

    assert has_element?(
             lv,
             ~s(#team-contacts-change[href="/teams/#{team.subdomain}/settings/contacts"])
           )
  end

  test "names the organization, with a link to Admins", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    organization_fixture([team], %{name: "Coastal SAR Association", logo: nil})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    assert has_element?(lv, "#settings-organization", "Coastal SAR Association")
    assert has_element?(lv, "#settings-organization-logo", "CS")

    assert has_element?(
             lv,
             ~s(#settings-organization a[href="/teams/#{team.subdomain}/settings/admins"])
           )
  end

  describe "Refresh from D4H" do
    test "takes the team's time zone from D4H, and leaves its names (#738)", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        Req.Test.json(conn, %{
          "id" => 1,
          "title" => "Renamed SAR",
          "timezone" => "America/Toronto"
        })
      end)

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

      assert lv |> element("#team-refresh") |> render_click() =~ "Team refreshed."
      assert has_element?(lv, "#team-timezone", "America/Toronto")
      assert %{timezone: "America/Toronto"} = refreshed = Team.get!(team.id)
      assert refreshed.name == team.name
    end

    test "says D4H refused, rather than crashing, when the key is turned down", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Unauthorized"})
      end)

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

      assert lv |> element("#team-refresh") |> render_click() =~ "D4H refused it"
      assert Team.get!(team.id).name == team.name
    end
  end

  test "404s for a team the user doesn't manage", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    other = team_fixture()

    assert_error_sent 404, fn ->
      conn |> log_in_user(user) |> get(~p"/teams/#{other}/settings")
    end
  end
end
