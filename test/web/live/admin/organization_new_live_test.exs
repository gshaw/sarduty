defmodule Web.Admin.OrganizationNewLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Organization

  setup %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    %{conn: log_in_user(conn, make_admin(user))}
  end

  test "a SAR Duty admin creates one, then adds its organization admins", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/orgs/new")
    assert has_element?(lv, ~s|#organization-cancel[href="#{~p"/admin/orgs"}"]|)

    {:ok, _lv, html} =
      lv
      |> form("#organization-form",
        organization: %{
          name: "BC Search and Rescue Association",
          short_name: "BCSARA",
          slug: "BCSARA",
          timezone: "America/Vancouver"
        }
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/orgs/bcsara/settings/admins")

    assert html =~ "Add an organization admin"
    assert %Organization{timezone: "America/Vancouver"} = Organization.get_by_slug("bcsara")
  end

  test "a slug in use is a field error", %{conn: conn} do
    organization_fixture([], %{slug: "bcsara"})
    {:ok, lv, _html} = live(conn, ~p"/admin/orgs/new")

    html =
      lv
      |> form("#organization-form",
        organization: %{
          name: "Other",
          short_name: "O",
          slug: "bcsara",
          timezone: "America/Vancouver"
        }
      )
      |> render_submit()

    assert html =~ "Another organization uses this slug."
  end

  test "the list shows each organization's admins, and None when it has none", %{conn: conn} do
    with_admin = organization_fixture()
    without = organization_fixture()
    organization_admin_fixture(with_admin, "dana@example.org")

    {:ok, lv, _html} = live(conn, ~p"/admin/orgs")

    assert has_element?(lv, "#organization-#{with_admin.id}", "dana@example.org")
    assert has_element?(lv, "#organization-#{without.id}-no-admins", "None")
  end

  test "/admin/orgs/:id is gone", %{conn: conn} do
    organization = organization_fixture()
    assert conn |> get("/admin/orgs/#{organization.id}") |> response(404)
  end
end
