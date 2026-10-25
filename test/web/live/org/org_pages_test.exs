defmodule Web.Org.OrgPagesTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import Ecto.Query
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Accounts.User
  alias App.Model.Event
  alias App.Model.Organization
  alias App.Model.OrganizationAdmin
  alias App.Repo

  # Dana is an organization admin of WSARA and a team admin of Coast Range, one of its
  # teams, as in #512's mockups.
  setup %{conn: conn} do
    %{user: dana, team: coast} = user_with_team_fixture(%{team: %{name: "Coast Range SAR"}})
    other_team = team_fixture(%{name: "Valley SAR"})

    organization =
      organization_fixture([coast, other_team], %{
        name: "Western SAR Association",
        short_name: "WSARA",
        slug: "wsara"
      })

    organization_admin_fixture(organization, dana.email)

    %{
      conn: conn,
      dana: dana,
      coast: coast,
      other_team: other_team,
      organization: organization
    }
  end

  defp events(kind), do: Event |> where([e], e.kind == ^kind) |> Repo.all()

  defp sar_duty_admin do
    admin = user_fixture(%{is_admin: true})
    # A SAR Duty admin logs in only while D4H lists them somewhere (#141).
    member_fixture(team_fixture(), %{email: admin.email, d4h_permission: 2})
    admin
  end

  describe "access" do
    test "an organization admin opens its pages", %{conn: conn, dana: dana} do
      conn = log_in_user(conn, dana)

      for path <- ~w(/orgs/wsara /orgs/wsara/settings /orgs/wsara/settings/admins
                     /orgs/wsara/settings/hours-tags) do
        assert {:ok, _lv, _html} = live(conn, path)
      end
    end

    test "an organization admin gets a 404 on another organization and its teams' pages",
         %{conn: conn, other_team: other_team} do
      organization_fixture([], %{slug: "nsara"})
      dana_only = user_fixture()
      organization = Repo.get_by!(Organization, slug: "wsara")
      organization_admin_fixture(organization, dana_only.email)
      conn = log_in_user(conn, dana_only)

      assert_error_sent 404, fn -> get(conn, ~p"/orgs/nsara") end
      assert_error_sent 404, fn -> get(conn, ~p"/orgs/missing") end
      assert_error_sent 404, fn -> get(conn, ~p"/teams/#{other_team}") end
    end

    test "a team admin of a member team gets a 404", %{conn: conn, other_team: other_team} do
      user = user_fixture()
      manager_fixture(other_team, %{email: user.email})

      assert_error_sent 404, fn -> conn |> log_in_user(user) |> get(~p"/orgs/wsara") end
    end

    test "a SAR Duty admin opens any organization's pages", %{conn: conn} do
      conn = log_in_user(conn, sar_duty_admin())
      assert {:ok, _lv, html} = live(conn, ~p"/orgs/wsara")
      assert html =~ "Coast Range SAR"
    end

    test "an organization admin with no team lands on the organization after logging in" do
      user = user_fixture()
      organization = Repo.get_by!(Organization, slug: "wsara")
      organization_admin_fixture(organization, user.email)

      assert Web.UserAuth.signed_in_path(user) == ~p"/orgs/wsara"
    end

    test "opening a page stamps their Last seen, not users.last_seen_at",
         %{conn: conn, dana: dana, organization: organization} do
      {:ok, _lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara")

      assert [%{last_seen_at: %DateTime{}}] = OrganizationAdmin.get_for_organization(organization)
      assert Repo.get!(User, dana.id).last_seen_at == nil
    end

    test "the switcher lists the organization", %{conn: conn, dana: dana, coast: coast} do
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/teams/#{coast}")
      assert has_element?(lv, "#switch-org-wsara", "Western SAR Association")
      assert has_element?(lv, "#switch-team-#{coast.subdomain}")
    end
  end

  describe "Teams" do
    test "lists its teams with counts and no people", %{conn: conn, dana: dana, coast: coast} do
      member_fixture(coast, %{name: "Wren Adams"})
      member_fixture(coast, %{name: "Bot", not_a_person: true})

      {:ok, lv, html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara")

      assert has_element?(lv, "#team-#{coast.id}-name", "Coast Range SAR")
      # Dana, and Wren; the bot is not a person.
      assert has_element?(lv, "#team-#{coast.id}-members", "2")
      assert has_element?(lv, "#team-#{coast.id}-refresh", "Never refreshed")
      refute html =~ "Wren Adams"
      refute has_element?(lv, "#search")
    end
  end

  describe "General" do
    test "an organization admin saves the name and time zone; the slug stays",
         %{conn: conn, dana: dana, organization: organization} do
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/settings")

      lv
      |> form("#organization-form",
        organization: %{name: "Western Search and Rescue", timezone: "America/Toronto"}
      )
      |> render_submit()

      saved = Repo.reload!(organization)
      assert saved.name == "Western Search and Rescue"
      assert saved.timezone == "America/Toronto"
      assert saved.slug == "wsara"
    end

    test "a new logo is sized for Wallet", %{conn: conn, dana: dana, organization: organization} do
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/settings")

      logo =
        file_input(lv, "#organization-form", :logo, [
          %{name: "logo.png", content: png_fixture(900, 300), type: "image/png"}
        ])

      render_upload(logo, "logo.png")
      lv |> form("#organization-form") |> render_submit()

      assert {:ok, image} = Image.from_binary(Repo.reload!(organization).logo)
      assert Image.width(image) == 480
    end

    test "a time zone not on the list is refused", %{conn: conn, dana: dana} do
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/settings")

      html = render_submit(lv, "save", %{organization: %{timezone: "Mars/Olympus"}})
      assert html =~ "Select a time zone."
    end
  end

  describe "Organization admins" do
    test "a SAR Duty admin adds and removes them", %{conn: conn, organization: organization} do
      {:ok, lv, _html} =
        conn |> log_in_user(sar_duty_admin()) |> live(~p"/orgs/wsara/settings/admins")

      lv
      |> form("#organization-admin-form",
        organization_admin: %{email: "Office@WSARA.example.org", reason: "Office"}
      )
      |> render_submit()

      added = Repo.get_by!(OrganizationAdmin, email: "office@wsara.example.org")
      assert has_element?(lv, "#organization-admin-#{added.id}", "office@wsara.example.org")

      lv |> element("#remove-organization-admin-#{added.id}") |> render_click()
      refute Repo.get(OrganizationAdmin, added.id)
      assert length(OrganizationAdmin.get_for_organization(organization)) == 1
    end

    test "an organization admin sees the list and SAR Duty admins, and can't change it",
         %{conn: conn, dana: dana, organization: organization} do
      sar_duty_admin = sar_duty_admin()
      [row] = OrganizationAdmin.get_for_organization(organization)
      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/settings/admins")

      assert has_element?(lv, "#organization-admin-#{row.id}")
      assert has_element?(lv, "#sar-duty-admin-emails", sar_duty_admin.email)
      refute has_element?(lv, "#organization-admin-form")
      refute has_element?(lv, "#remove-organization-admin-#{row.id}")

      render_hook(lv, "add", %{organization_admin: %{email: "friend@example.org"}})
      render_hook(lv, "remove", %{id: row.id})

      assert [%{id: id}] = OrganizationAdmin.get_for_organization(organization)
      assert id == row.id
      assert events(:organization_admin_added) == []
    end
  end

  describe "Hours tags" do
    test "offers its teams' tags, counts them, and records the change",
         %{
           conn: conn,
           dana: dana,
           coast: coast,
           other_team: other_team,
           organization: organization
         } do
      tag_fixture(coast, "SRVTC Primary")
      tag_fixture(other_team, "SRVTC Primary")
      tag_fixture(coast, "Social")

      {:ok, lv, html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/settings/hours-tags")
      assert html =~ "SRVTC Primary"

      html =
        lv
        |> form("#hours-tags-form", organization: %{primary_hours_tag: "SRVTC Primary"})
        |> render_change()

      assert html =~ "2 of 2 teams have this tag."

      lv
      |> form("#hours-tags-form", organization: %{primary_hours_tag: "SRVTC Primary"})
      |> render_submit()

      assert Repo.reload!(organization).primary_hours_tag == "SRVTC Primary"

      assert [event] = events(:organization_hours_tags_changed)

      assert event.user_id == dana.id
      assert event.data["after"]["primary"] == "SRVTC Primary"
    end

    test "a tag a team uses for other hours is refused, naming the team",
         %{conn: conn, dana: dana, coast: coast} do
      coast |> Ecto.Changeset.change(secondary_hours_tag: "Training") |> Repo.update!()
      tag_fixture(coast, "Training")

      {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/orgs/wsara/settings/hours-tags")

      html =
        lv
        |> form("#hours-tags-form", organization: %{primary_hours_tag: "Training"})
        |> render_submit()

      assert html =~ "Coast Range SAR uses Training for another kind of hours."
    end
  end

  # Every org page, from the router, as an organization admin, with members' names,
  # emails, and phones seeded: none of them shows. A new org page joins with no change
  # here.
  describe "no people" do
    test "no org page shows a member's name, email, or phone",
         %{conn: conn, dana: dana, coast: coast, other_team: other_team} do
      people =
        for team <- [coast, other_team] do
          member_fixture(team, %{
            name: "Quill Ostrander",
            email: "quill@example.com",
            phone: "604-555-0199"
          })
        end

      conn = log_in_user(conn, dana)

      paths =
        for %{path: "/orgs/:slug" <> _rest = path, plug: Phoenix.LiveView.Plug} <-
              Web.Router.__routes__() do
          path
          |> String.replace(":slug", "wsara")
          |> String.replace(":subdomain", coast.subdomain)
        end

      assert "/orgs/wsara" in paths

      for path <- paths, person <- people do
        html =
          case live(conn, path) do
            {:ok, _lv, html} -> html
            {:error, {_kind, %{to: to}}} -> flunk("#{path} redirected to #{to}")
          end

        for value <- [person.name, person.email, person.phone] do
          refute html =~ value, "#{path} shows #{value}"
        end
      end
    end
  end
end
