defmodule Web.AccountLiveTest do
  use Web.ConnCase

  import App.AccountsFixtures
  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  test "is Account settings: the email, and the account menu", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    other = team_fixture(%{name: "Other SAR"})
    manager_fixture(other, %{email: user.email})

    {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "h1", "Account settings")
    assert has_element?(lv, "#account-email", user.email)
    assert has_element?(lv, "#nav-area", "Account settings")
    assert has_element?(lv, ~s{#account-menu #nav-account-settings[href="/account"]})
    assert has_element?(lv, ~s{#switch-team-#{team.subdomain}[href="/teams/#{team.subdomain}"]})
    refute has_element?(lv, "#side-nav")
    refute html =~ "Change password"
  end

  test "saves the maps app place links open", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "#maps-app-google[checked]")

    lv |> form("#maps-app-form", %{maps_app: "apple"}) |> render_change()

    assert has_element?(lv, "#maps-app-apple[checked]")
    assert Repo.reload!(user).maps_app == "apple"

    lv |> element("#maps-app-form") |> render_change(%{maps_app: "bing"})
    assert Repo.reload!(user).maps_app == "apple"
  end

  test "a user who manages no team sees no team settings", %{conn: conn} do
    {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    refute html =~ "Team settings"
  end

  test "an invitation reminders switch for the team the user logs in to (#444)",
       %{conn: conn} do
    %{member: member, user: user} = member_with_login_fixture()
    id = "#invitation-reminders-#{member.team.subdomain}"
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "#emails h2", "Emails")

    assert has_element?(
             lv,
             "label[for=#{String.trim_leading(id, "#")}]",
             ~r/^\s*Invitation reminders\s*$/
           )

    assert has_element?(lv, "#{id}[checked]")

    lv |> element(id) |> render_click()
    refute Repo.reload(member).invitation_reminders
    refute has_element?(lv, "#{id}[checked]")

    lv |> element(id) |> render_click()
    assert Repo.reload(member).invitation_reminders
  end

  test "names the team when the user logs in to several", %{conn: conn} do
    %{member: member, user: user} = member_with_login_fixture()
    other = member_logins_team_fixture(%{name: "Other SAR"})
    other_member = member_fixture(other, %{email: user.email})
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    assert has_element?(lv, "#emails", "Invitation reminders from #{member.team.name}")
    assert has_element?(lv, "#emails", "Invitation reminders from Other SAR")

    lv |> element("#invitation-reminders-#{other.subdomain}") |> render_click()
    refute Repo.reload(other_member).invitation_reminders
    assert Repo.reload(member).invitation_reminders
  end

  test "taps only change the user's own members", %{conn: conn} do
    %{user: user} = member_with_login_fixture()
    %{member: someone} = member_with_login_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

    render_click(lv, "reminders", %{"id" => to_string(someone.id)})
    assert Repo.reload(someone).invitation_reminders
  end

  test "no Emails without a member login", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")

    refute has_element?(lv, "#emails")
  end

  test "a team admin viewing as a member cannot change their own reminders (#425)",
       %{conn: conn} do
    %{team: team, member: sam} = member_with_login_fixture()
    admin = user_fixture()
    own = manager_fixture(team, %{email: admin.email})
    conn = conn |> log_in_user(admin) |> post(~p"/teams/#{team}/members/#{sam}/view-as")
    {:ok, lv, _html} = live(conn, ~p"/account")

    assert has_element?(lv, "#emails-view-as")
    assert has_element?(lv, "#invitation-reminders-#{team.subdomain}[disabled]")

    render_click(lv, "reminders", %{"id" => to_string(own.id)})
    assert Repo.reload(own).invitation_reminders
    assert Repo.reload(sam).invitation_reminders
  end

  test "redirects if user is not logged in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account")
  end
end
