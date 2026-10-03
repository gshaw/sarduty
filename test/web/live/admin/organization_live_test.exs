defmodule Web.Admin.OrganizationLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Organization
  alias App.Model.Team

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, make_admin(user)), team: team}
  end

  test "an admin creates an organization with a logo and member teams", %{conn: conn, team: team} do
    other = team_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/organizations/new")

    logo =
      file_input(lv, "#organization-form", :logo, [
        %{name: "logo.png", content: png_fixture(900, 300), type: "image/png"}
      ])

    render_upload(logo, "logo.png")

    {:ok, _lv, html} =
      lv
      |> form("#organization-form",
        organization: %{
          name: "BC Search and Rescue Association",
          short_name: "BCSARA",
          slug: "BCSARA",
          website: "https://bcsara.com"
        }
      )
      |> render_submit(%{team_ids: ["", "#{team.id}"]})
      |> follow_redirect(conn)

    organization = Organization.get_by_slug("bcsara")
    assert html =~ "verify.bcsara.com"
    assert {:ok, image} = Image.from_binary(organization.logo)
    assert Image.width(image) == 480
    assert Team.get!(team.id).organization_id == organization.id
    assert Team.get!(other.id).organization_id == nil
  end

  test "clearing a team's box takes it out", %{conn: conn, team: team} do
    organization = organization_fixture([team])
    {:ok, lv, _html} = live(conn, ~p"/admin/organizations/#{organization.id}")

    lv |> form("#organization-form") |> render_submit(%{team_ids: [""]})

    assert Team.get!(team.id).organization_id == nil
  end

  test "a bad slug shows an error and saves nothing", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/organizations/new")

    html =
      lv
      |> form("#organization-form",
        organization: %{name: "Example", short_name: "EX", slug: "has space"}
      )
      |> render_submit()

    assert html =~ "lowercase letters"
    assert Organization.get_all() == []
  end

  test "lists organizations with their teams", %{conn: conn, team: team} do
    organization = organization_fixture([team])
    {:ok, lv, _html} = live(conn, ~p"/admin/organizations")

    assert has_element?(lv, "#organization-#{organization.id}", team.name)
  end

  test "non-admins can't open it" do
    %{user: user} = user_with_team_fixture()
    conn = log_in_user(build_conn(), user)

    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/organizations")
  end
end
