defmodule Web.Settings.MemberLoginsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Accounts
  alias App.Model.Event
  alias App.Model.Team
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    %{conn: log_in_user(conn, user), user: user, team: team}
  end

  test "is off until a team admin turns it on, and then members may log in",
       %{conn: conn, team: team} do
    member = member_fixture(team, %{d4h_permission: 2})
    refute Accounts.may_log_in?(member.email)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/member-logins")
    assert has_element?(lv, ".tabs a[aria-current=page]", "Member logins")
    refute has_element?(lv, "#member-logins-form input[type=checkbox][checked]")

    lv
    |> form("#member-logins-form", team: %{member_logins: "true"})
    |> render_submit()

    assert Repo.reload!(team).member_logins
    assert Accounts.may_log_in?(member.email)
    assert Event.get_last(:member_logins_turned_on).team_id == team.id

    lv
    |> form("#member-logins-form", team: %{member_logins: "false"})
    |> render_submit()

    refute Repo.reload!(team).member_logins
    refute Accounts.may_log_in?(member.email)
  end

  test "chores stay hidden until a team admin turns them on", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/member-logins")

    lv
    |> form("#member-logins-form", team: %{member_logins: "true"})
    |> render_submit()

    refute team |> Repo.reload!() |> Team.chores?()
    refute has_element?(lv, ".tabs a", "Chore categories")

    lv
    |> form("#member-logins-form", team: %{member_logins: "true", chores_enabled: "true"})
    |> render_submit()

    assert team |> Repo.reload!() |> Team.chores?()
    assert has_element?(lv, ".tabs a", "Chore categories")
  end
end
