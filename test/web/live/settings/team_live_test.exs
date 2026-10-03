defmodule Web.Settings.TeamLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team

  @secret "SECRET-TEAM-PAT-123"

  test "renders team settings when team exists", %{conn: conn} do
    %{user: user} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/settings/team")

    assert html =~ "Team settings"
  end

  test "never puts the saved team key in the page", %{conn: conn} do
    %{user: user} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_saved_at: ~U[2026-08-01 18:00:00Z]}
      })

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/settings/team")

    refute html =~ @secret
    refute render(lv) =~ @secret
    assert has_element?(lv, "#form_new_d4h_access_key")
    refute has_element?(lv, "#form_new_d4h_access_key[value]")
    assert has_element?(lv, "#team-key-status", "Key saved August 1, 2026")
  end

  test "says when no team key is saved", %{conn: conn} do
    %{user: user} = user_with_team_fixture()

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/settings/team")

    assert has_element?(lv, "#team-key-status", "No team key saved")
  end

  test "saving with a blank key field keeps the saved key", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: @secret}})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/settings/team")

    html =
      lv
      |> form("form", form: %{name: "Renamed SAR", new_d4h_access_key: ""})
      |> render_submit()

    assert html =~ "Changes saved"
    refute html =~ @secret

    team = Team.get!(team.id)
    assert team.name == "Renamed SAR"
    assert team.d4h_access_key == @secret
  end

  test "names the key's D4H member and asks for a SAR Duty account", %{conn: conn} do
    %{user: user} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_owner: "Sam Rivers"}
      })

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/settings/team")

    assert has_element?(lv, "#team-key-owner", "Sam Rivers")
    assert has_element?(lv, "#team-key-advice", "SAR Duty")
  end

  test "drops the advice once the key is a SAR Duty account's", %{conn: conn} do
    %{user: user} =
      user_with_team_fixture(%{
        team: %{d4h_access_key: @secret, d4h_access_key_owner: "SAR Duty"}
      })

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/settings/team")

    assert has_element?(lv, "#team-key-owner", "SAR Duty")
    refute has_element?(lv, "#team-key-advice")
  end
end
