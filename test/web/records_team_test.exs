defmodule Web.RecordsTeamTest do
  # A team on SAR Duty Records (docs/records.md) has no D4H: no page links to D4H, and
  # the words that say where its records are name Records.
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{user: user, team: team} =
      records_team_with_user_fixture(%{d4h_access_key_owner: "SAR Duty"})

    %{conn: log_in_user(conn, user), team: team}
  end

  test "no page links to D4H", %{conn: conn, team: team} do
    member = member_fixture(team)
    activity = activity_fixture(team)
    group = group_fixture(team)
    qualification = qualification_fixture(team)

    paths = [
      ~p"/teams/#{team}",
      ~p"/teams/#{team}/members/#{member.id}",
      ~p"/teams/#{team}/activities/#{activity.id}",
      ~p"/teams/#{team}/groups/#{group.id}",
      ~p"/teams/#{team}/qualifications/#{qualification.id}"
    ]

    for path <- paths do
      {:ok, lv, _html} = live(conn, path)
      refute has_element?(lv, "a", "Open D4H"), path
    end
  end

  test "the team home names Records", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    assert has_element?(lv, "#d4h-updated", "SAR Duty Records")
    assert has_element?(lv, "#coming-up-empty", "SAR Duty Records")
  end

  test "team settings asks for a Records access key", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")
    assert has_element?(lv, "label", "Records access key")
    assert has_element?(lv, "#team-key-owner", "SAR Duty")
    assert has_element?(lv, "#records-keys")
    refute has_element?(lv, "#team-key-advice")
  end

  test "a D4H team still links to D4H", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")
    assert has_element?(lv, "a", "Open D4H member")
  end
end
