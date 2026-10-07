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
      |> live(~p"/teams/#{team}/qualifications")

    assert html =~ "Qualifications"
    assert html =~ "First Aid"
  end

  test "renders empty qualifications page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications")

    assert html =~ "Qualifications"
    assert html =~ "0 qualifications"
  end

  test "links to qualification detail page", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification_fixture(team, %{title: "Swift Water Rescue"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications")

    assert has_element?(lv, "a", "Swift Water Rescue")
  end

  test "the expiring view lists each current member's latest award ending in 60 days",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "First Aid"})
    soon = DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.truncate(:second)
    later = DateTime.add(soon, 400, :day)

    expiring = member_fixture(team, %{name: "Expiring Member"})
    qualification_award_fixture(qualification, expiring, %{ends_at: soon})

    renewed = member_fixture(team, %{name: "Renewed Member"})
    qualification_award_fixture(qualification, renewed, %{ends_at: soon})
    qualification_award_fixture(qualification, renewed, %{ends_at: later})

    departed = member_fixture(team, %{name: "Departed Member", left_at: ~U[2025-01-01 00:00:00Z]})
    qualification_award_fixture(qualification, departed, %{ends_at: soon})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/qualifications?view=expiring")

    assert has_element?(lv, "#expiring-#{expiring.id}-#{qualification.id}", "First Aid")
    refute has_element?(lv, "#expiring_qualifications", "Renewed Member")
    refute has_element?(lv, "#expiring_qualifications", "Departed Member")
  end
end
