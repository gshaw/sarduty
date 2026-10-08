defmodule Web.Admin.TeamLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Team

  setup %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    %{conn: log_in_user(conn, make_admin(user))}
  end

  test "an admin creates a team without D4H and lands on its home", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/teams/new")

    {:ok, _lv, html} =
      lv
      |> form("#hosted-team-form",
        form: %{
          name: "Kings County SAR",
          subdomain: "kings-county",
          timezone: "America/Halifax",
          manager_name: "Robin Example",
          manager_email: "robin@example.com"
        }
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/kings-county")

    assert html =~ "Created Kings County SAR."
    assert Team.get_by(subdomain: "kings-county")
  end

  test "its settings have no D4H key", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/teams/new")

    lv
    |> form("#hosted-team-form",
      form: %{
        name: "Hill SAR",
        subdomain: "hill-team",
        timezone: "America/Halifax",
        manager_name: "Robin Example",
        manager_email: "robin@example.com"
      }
    )
    |> render_submit()

    {:ok, settings, _html} = live(conn, ~p"/teams/hill-team/settings")
    assert has_element?(settings, "#team-hosted")
    refute has_element?(settings, "#team_settings_form_new_d4h_access_key")
  end

  test "a team's address must be free", %{conn: conn} do
    taken = team_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/teams/new")

    html =
      lv
      |> form("#hosted-team-form",
        form: %{
          name: "Taken",
          subdomain: taken.subdomain,
          timezone: "America/Halifax",
          manager_name: "Robin Example",
          manager_email: "robin@example.com"
        }
      )
      |> render_submit()

    assert html =~ "Another team uses this one."
  end
end
