defmodule Web.ViewAsControllerTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.AccountsFixtures
  alias App.Model.Event
  alias App.Model.TaxCreditLetter
  alias App.Repo

  # A team admin views the team as a member (#425): the member's pages, read-only.
  setup %{conn: conn} do
    %{team: team, member: sam, user: sam_user} = member_with_login_fixture(%{name: "Sam Rivera"})
    admin = AccountsFixtures.user_fixture()
    manager_fixture(team, %{email: admin.email, name: "Alex Chen"})

    test_pid = self()

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      send(test_pid, {:d4h, conn.method, conn.request_path})
      Req.Test.json(conn, %{})
    end)

    %{conn: log_in_user(conn, admin), team: team, sam: sam, sam_user: sam_user, admin: admin}
  end

  defp view_as(conn, team, member), do: post(conn, ~p"/teams/#{team}/members/#{member}/view-as")

  defp open(conn, path) do
    {:ok, lv, _html} = live(conn, path)
    render_async(lv)
    lv
  end

  test "a team admin sees the member's pages, with the banner",
       %{conn: conn, team: team, sam: sam, admin: admin} do
    conn = view_as(conn, team, sam)
    assert redirected_to(conn) == ~p"/teams/#{team}/me"

    lv = open(conn, ~p"/teams/#{team}/me")
    assert has_element?(lv, "h1", "Sam Rivera")
    assert has_element?(lv, "#view-as-banner", "Viewing as Sam Rivera")
    assert has_element?(lv, "#view-as-banner", "Nothing you do here is saved")
    # The member's side navigation, and the team admin's own account menu.
    assert has_element?(lv, "#side-nav-me")
    refute has_element?(lv, "#side-nav-groups")
    assert has_element?(lv, "#account-menu .menu-name", "Alex Chen")
    # Sam's photo, not the team admin's.
    assert has_element?(
             lv,
             ~s{#member-head-photo[src="/teams/#{team.subdomain}/members/#{sam.id}/image"]}
           )

    lv = open(conn, ~p"/teams/#{team}")
    assert has_element?(lv, "#view-as-banner")
    refute has_element?(lv, "#side-nav-groups")

    assert [event] = Event.get_recent(%{kind: :member_viewed_as}, 10)
    assert event.user_id == admin.id
    assert event.team_id == team.id
    assert event.data == %{"member_id" => sam.id}
  end

  test "team admin pages stay the team admin's", %{conn: conn, team: team, sam: sam} do
    conn = view_as(conn, team, sam)

    lv = open(conn, ~p"/teams/#{team}/groups")
    assert has_element?(lv, "#side-nav-groups")
    assert has_element?(lv, "#view-as-banner", "This page is yours as a team admin")
  end

  test "Stop viewing goes back to the member's page", %{conn: conn, team: team, sam: sam} do
    conn = view_as(conn, team, sam)
    conn = delete(conn, ~p"/teams/#{team}/view-as")
    assert redirected_to(conn) == ~p"/teams/#{team}/members/#{sam}"

    # The team admin is a member too, so Your membership is theirs again.
    lv = open(conn, ~p"/teams/#{team}/me")
    assert has_element?(lv, "h1", "Alex Chen")
    refute has_element?(lv, "#view-as-banner")
  end

  test "the member page has the button", %{conn: conn, team: team, sam: sam} do
    lv = open(conn, ~p"/teams/#{team}/members/#{sam}")

    assert has_element?(
             lv,
             ~s{#view-as[href="/teams/#{team.subdomain}/members/#{sam.id}/view-as"]}
           )
  end

  test "only for the team's own members", %{conn: conn, team: team} do
    other = member_fixture(team_fixture())

    assert_error_sent 404, fn -> view_as(conn, team, other) end
  end

  test "a member can't view as another member", %{team: team, sam: sam} do
    %{user: pat} = member_on(team)
    conn = log_in_user(build_conn(), pat)

    assert_error_sent 404, fn -> view_as(conn, team, sam) end
  end

  test "a view-as on one team leaves another team alone",
       %{conn: conn, team: team, sam: sam, admin: admin} do
    other_team = team_fixture()
    conn = view_as(conn, team, sam)
    manager_fixture(other_team, %{email: admin.email})

    lv = open(conn, ~p"/teams/#{other_team}")
    refute has_element?(lv, "#view-as-banner")
  end

  test "an error report names the member and the team admin",
       %{conn: conn, team: team, sam: sam, admin: admin} do
    letter = tax_credit_letter_fixture(sam)
    conn = view_as(conn, team, sam)

    # ConnTest runs the request in the test process, so its Logger metadata is ours.
    get(conn, ~p"/teams/#{team}/me/tax-credit-letters/#{letter.id}/pdf")
    context = Honeybadger.context()
    assert context.user_id == admin.id
    assert context.member_id == sam.id
    assert context.viewing_as
  end

  describe "read-only" do
    test "contact details save nothing", %{conn: conn, team: team, sam: sam} do
      conn = view_as(conn, team, sam)
      lv = open(conn, ~p"/teams/#{team}/me/details")
      assert has_element?(lv, "#details-form button[disabled]", "Save details")

      html = lv |> form("#details-form", details: %{address: "9 Elm St"}) |> render_submit()
      assert html =~ "You&#39;re viewing as Sam Rivera, so nothing is saved."
      refute_received {:d4h, "PATCH", _path}
    end

    # Web.UserAuth refuses the event before the page sees it (#440); chores had no
    # check of their own.
    test "chores save nothing", %{conn: conn, team: team, sam: sam} do
      chore = chore_fixture(sam, chore_category_fixture(team))
      conn = view_as(conn, team, sam)

      lv = open(conn, ~p"/teams/#{team}/me/chores")
      render_click(lv, "delete", %{"id" => "#{chore.id}"})
      assert has_element?(lv, "#flash-error", "so nothing is saved")

      lv = open(conn, ~p"/teams/#{team}/me/chores/#{chore.id}/edit")
      assert has_element?(lv, "#chore-save[disabled]")
      assert has_element?(lv, "#chore-delete[disabled]")
      render_click(lv, "delete", %{})
      lv |> form("#chore-form") |> render_submit()
      assert has_element?(lv, "#flash-error", "so nothing is saved")

      lv = open(conn, ~p"/teams/#{team}/me/chores/new")
      lv |> form("#chore-form") |> render_submit()

      assert [%{id: id}] = Repo.all(App.Model.Chore)
      assert id == chore.id
    end

    test "the letter downloads but stays on the member's to-do",
         %{conn: conn, team: team, sam: sam} do
      letter = tax_credit_letter_fixture(sam)
      conn = view_as(conn, team, sam)

      conn = get(conn, ~p"/teams/#{team}/me/tax-credit-letters/#{letter.id}/pdf")
      assert response(conn, 200)
      assert Repo.get!(TaxCreditLetter, letter.id).downloaded_at == nil
    end

    test "no Wallet pass", %{conn: conn, team: team, sam: sam} do
      conn = view_as(conn, team, sam)

      conn = get(conn, ~p"/teams/#{team}/me/card/apple-wallet")
      assert redirected_to(conn) == ~p"/teams/#{team}/me"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "viewing as Sam Rivera"
    end
  end

  # Another member of the team, with a login.
  defp member_on(team) do
    member = member_fixture(team, %{d4h_permission: 2})
    %{member: member, user: AccountsFixtures.user_fixture(%{email: member.email})}
  end
end
