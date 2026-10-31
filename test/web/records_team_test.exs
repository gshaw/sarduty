defmodule Web.RecordsTeamTest do
  # A team on SAR Duty Records (docs/records.md) has no D4H: no page links to D4H, and
  # the words that say where its records are name Records.
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{user: user, team: team} =
      records_team_with_user_fixture(%{
        d4h_access_key: "records-key",
        d4h_access_key_owner: "SAR Duty"
      })

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
      refute has_element?(lv, "a", "Open in D4H"), path
      refute has_element?(lv, "a", "Open in SAR Duty Records"), path
    end
  end

  test "every editing page opens", %{conn: conn, team: team} do
    member = member_fixture(team)
    activity = activity_fixture(team)
    group = group_fixture(team)
    qualification = qualification_fixture(team)

    paths = [
      ~p"/teams/#{team}/members/new",
      ~p"/teams/#{team}/members/#{member.id}/edit",
      ~p"/teams/#{team}/activities/new",
      ~p"/teams/#{team}/activities/#{activity.id}/edit",
      ~p"/teams/#{team}/groups/new",
      ~p"/teams/#{team}/groups/#{group.id}/edit",
      ~p"/teams/#{team}/qualifications/new",
      ~p"/teams/#{team}/qualifications/#{qualification.id}/edit"
    ]

    for path <- paths do
      assert get(conn, path).status == 200, path
    end
  end

  test "the team home says when it refreshed, not from where", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")
    assert has_element?(lv, "#d4h-updated", "refreshed")
    refute has_element?(lv, "#d4h-updated", "Records")
    refute has_element?(lv, "#open-d4h")
    assert has_element?(lv, "#coming-up-empty", "No activities planned.")
  end

  test "Access key asks for a Records access key, with no D4H check", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/access-key")
    assert has_element?(lv, "label", "Records access key")
    assert has_element?(lv, "#team-key-owner", "SAR Duty")
    assert has_element?(lv, "#records-keys")
    refute has_element?(lv, "#team-key-advice")
    refute has_element?(lv, "#key-rights")
  end

  # Records may have no place for a team, so the refresh keeps the one SAR Duty has.
  test "refreshing a team with no place keeps its place", %{conn: conn, team: team} do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      Req.Test.json(conn, %{
        "id" => team.d4h_team_id,
        "title" => "Demo SAR",
        "subdomain" => team.subdomain,
        "timezone" => "America/Halifax"
      })
    end)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings")

    assert lv |> element("button", "Refresh") |> render_click() =~
             "Team refreshed."

    team = App.Repo.reload!(team)
    assert team.lat == 49.2
  end

  test "a D4H team still links to D4H", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/members/#{member.id}")
    assert has_element?(lv, "a", "Open in D4H")
  end
end
