defmodule Web.Settings.HoursTagsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Activity
  alias App.Model.Team

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    for title <- ["Primary Hours", "Training Hrs", "No Hours"], do: tag_fixture(team, title)
    %{conn: log_in_user(conn, user), team: team}
  end

  test "a team names its hours tags from its D4H tags", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/hours-tags")

    lv
    |> form("#hours-tags-form",
      team: %{secondary_hours_tag: "Training Hrs", other_hours_tag: "No Hours"}
    )
    |> render_submit()

    assert render(lv) =~ "Hours tags saved."

    assert team.id |> Team.get!() |> Activity.hours_tags() == %{
             primary: "Primary Hours",
             secondary: "Training Hrs",
             other: "No Hours"
           }
  end

  test "a tag the organization names is locked", %{conn: conn, team: team} do
    organization_fixture([team], %{secondary_hours_tag: "SRVTC Secondary Activity"})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/hours-tags")

    assert has_element?(lv, "#hours-tag-secondary[disabled][value='SRVTC Secondary Activity']")
    assert render(lv) =~ "Set by"

    lv |> form("#hours-tags-form", team: %{other_hours_tag: "No Hours"}) |> render_submit()
    team = Team.get!(team.id)
    assert team.secondary_hours_tag == nil
    assert Activity.hours_tags(team).other == "No Hours"
  end

  test "the other tag must differ from the hours tags", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/hours-tags")

    html =
      lv
      |> form("#hours-tags-form", team: %{other_hours_tag: "Primary Hours"})
      |> render_submit()

    assert html =~ "Use a different tag from primary hours."
    assert Team.get!(team.id).other_hours_tag == nil
  end
end
