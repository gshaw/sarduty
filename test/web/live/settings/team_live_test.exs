defmodule Web.Settings.TeamLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team

  @secret "SECRET-TEAM-PAT-123"

  test "renders team settings when team exists", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/settings")

    assert html =~ "Team settings"
  end

  test "General has no key field; the key is on Access key (#727)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})

    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

    refute html =~ @secret
    refute has_element?(lv, "#form_new_d4h_access_key")

    assert has_element?(
             lv,
             ~s(a[href="/teams/#{team.subdomain}/settings/access-key"]),
             "Access key"
           )
  end

  test "saves the team's three names (#738)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")
    assert has_element?(lv, "#team-names-lead")

    names = %{
      name: "York Sunbury SAR",
      legal_name: "York Sunbury Search and Rescue Inc.",
      abbreviated_name: "YSSR"
    }

    lv |> form("#team_settings_form", form: names) |> render_submit()

    assert %{
             name: "York Sunbury SAR",
             legal_name: "York Sunbury Search and Rescue Inc.",
             abbreviated_name: "YSSR"
           } = Team.get!(team.id)
  end

  test "changes the team in the URL, not the one last opened", %{conn: conn} do
    %{user: user, team: first} = user_with_team_fixture()
    second = team_fixture(%{name: "Second SAR"})
    manager_fixture(second, %{email: user.email})
    App.Repo.update_all(App.Accounts.User, set: [last_team_id: first.id])

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{second}/settings")

    lv |> form("#team_settings_form", form: %{name: "Renamed Second"}) |> render_submit()

    assert Team.get!(second.id).name == "Renamed Second"
    assert Team.get!(first.id).name == first.name
  end

  describe "Refresh" do
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

      assert render_click(lv, "refresh", %{}) =~ "Team refreshed."
      assert %{timezone: "America/Toronto"} = refreshed = Team.get!(team.id)
      assert refreshed.name == team.name
    end

    test "says D4H refused, rather than crashing, when the key is turned down", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})

      Req.Test.stub(App.Adapter.D4H, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Unauthorized"})
      end)

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/settings")

      assert render_click(lv, "refresh", %{}) =~ "D4H refused it"
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
