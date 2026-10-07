defmodule Web.MemberCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders members collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members")

    assert html =~ "Members"
  end

  test "lists current members missing a photo, mobile phone, or email, and what they lack",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    no_phone = member_fixture(team, %{phone: nil, has_photo: false})
    no_email = member_fixture(team, %{email: ""})
    complete = member_fixture(team)
    unchecked = member_fixture(team, %{has_photo: nil})
    departed = member_fixture(team, %{phone: nil, left_at: ~U[2025-01-01 00:00:00Z]})
    other_team = member_fixture(team_fixture(), %{phone: nil})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/members?details=missing")

    assert has_element?(lv, "#missing-#{no_phone.id}", "Photo, Mobile phone")
    assert has_element?(lv, "#missing-#{no_email.id}", "Email")
    refute has_element?(lv, "#missing-#{complete.id}")
    refute has_element?(lv, "#missing-#{unchecked.id}")
    refute has_element?(lv, "#missing-#{departed.id}")
    refute has_element?(lv, "#missing-#{other_team.id}")
  end
end
