defmodule Web.QualificationCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders qualifications page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "First Aid"})
    member = member_fixture(team)
    qualification_award_fixture(qualification, member)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/qualifications")

    assert html =~ "Qualifications"
    assert html =~ "First Aid"
  end

  test "renders empty qualifications page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/qualifications")

    assert html =~ "Qualifications"
    assert html =~ "0 qualifications"
  end

  test "links to qualification detail page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification_fixture(team, %{title: "Swift Water Rescue"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/qualifications")

    assert has_element?(lv, "a", "Swift Water Rescue")
  end
end
