defmodule Web.MemberLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

  test "renders member page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members/#{member.id}")

    assert html =~ member.name
  end

  test "suggests marking a bot, and the switch marks it not a person", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    bot = member_fixture(team, %{name: "Roster Bot", phone: nil, email: nil})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{bot.id}")

    assert has_element?(lv, "#not-a-person-suggestion")
    refute has_element?(lv, "#not-a-person-switch[checked]")

    lv |> element("#not-a-person-switch") |> render_click()

    assert has_element?(lv, "#not-a-person-switch[checked]")
    refute has_element?(lv, "#not-a-person-suggestion")
    assert Repo.reload!(bot).not_a_person

    lv |> element("#not-a-person-switch") |> render_click()

    refute Repo.reload!(bot).not_a_person
  end

  test "does not suggest marking a member with attendance", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{phone: nil, email: nil})
    attendance_fixture(activity_fixture(team), member)

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")

    refute has_element?(lv, "#not-a-person-suggestion")
  end
end
