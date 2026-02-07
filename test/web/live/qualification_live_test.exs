defmodule Web.QualificationLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders qualification page with active and expired awards", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "Rope Rescue"})

    active_member = member_fixture(team, %{name: "Alice Active"})

    qualification_award_fixture(qualification, active_member, %{
      starts_at: DateTime.add(DateTime.utc_now(), -365, :day),
      ends_at: DateTime.add(DateTime.utc_now(), 365, :day)
    })

    expired_member = member_fixture(team, %{name: "Bob Expired"})

    qualification_award_fixture(qualification, expired_member, %{
      starts_at: DateTime.add(DateTime.utc_now(), -730, :day),
      ends_at: DateTime.add(DateTime.utc_now(), -365, :day)
    })

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/qualifications/#{qualification.id}")

    assert html =~ "Rope Rescue"
    assert html =~ "Alice Active"
    assert html =~ "Bob Expired"
  end

  test "renders qualification page with no awards", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    qualification = qualification_fixture(team, %{title: "Empty Qual"})

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/qualifications/#{qualification.id}")

    assert html =~ "Empty Qual"
    assert html =~ "No active awards"
    assert html =~ "No expired awards"
  end
end
