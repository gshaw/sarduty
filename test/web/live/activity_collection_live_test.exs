defmodule Web.ActivityCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders activities collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/activities")

    assert html =~ "Activities"
    assert page_title(lv) =~ "Activities"
  end

  test "leaves out activities deleted in D4H", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    listed = activity_fixture(team, %{title: "Rope rescue night"})
    activity_fixture(team, %{title: "NO MIT Training", deleted_at: ~U[2026-10-05 06:00:00Z]})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")

    assert has_element?(lv, "#activity_collection", listed.title)
    refute has_element?(lv, "#activity_collection", "NO MIT Training")
  end

  test "chore activities have their own tile, with their members' total (#575)", %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{team: %{member_logins: true, chores_enabled: true}})

    activity_fixture(team, %{title: "Board meeting", activity_kind: "event"})
    chore_activity_fixture(team, [90, 30])

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")

    assert has_element?(lv, "#activity-tile-event", "1")
    assert has_element?(lv, "#activity-tile-all", "2")
    assert has_element?(lv, "#activity-tile-chores", "1")
    assert has_element?(lv, "#activity_collection", "Chores: Equipment maintenance")

    lv |> element("#activity-tile-chores") |> render_click()

    assert has_element?(lv, "#activity_collection", "Chores: Equipment maintenance")
    assert has_element?(lv, "#activity_collection", "2 hours")
    refute has_element?(lv, "#activity_collection", "Board meeting")
  end

  test "Date: the day, its start and end under it with +1 overnight, and a chore activity's month",
       %{conn: conn} do
    %{user: user, team: team} =
      user_with_team_fixture(%{team: %{member_logins: true, chores_enabled: true}})

    activity_fixture(team, %{
      title: "Overnight search",
      started_at: ~U[2026-09-04 06:00:00Z],
      finished_at: ~U[2026-09-04 09:00:00Z]
    })

    chore_activity_fixture(team, [60], %{
      started_at: ~U[2026-10-01 07:00:00Z],
      finished_at: ~U[2026-10-01 07:00:00Z]
    })

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?when=all")

    assert has_element?(lv, "#activity_collection td", "Sep 3, 2026")
    assert has_element?(lv, "#activity_collection td .hint", "23:00–02:00")
    assert has_element?(lv, "#activity_collection td .hint sup", "+1")
    assert has_element?(lv, "#activity_collection td", "Oct 2026")
    refute has_element?(lv, "#activity_collection td", "Oct 1, 2026")
  end

  test "Draft follows the title once an unpublished activity has finished, not before",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    now = DateTime.utc_now()

    done =
      activity_fixture(team, %{
        is_published: false,
        started_at: DateTime.add(now, -3, :hour),
        finished_at: DateTime.add(now, -1, :hour)
      })

    coming =
      activity_fixture(team, %{
        is_published: false,
        started_at: DateTime.add(now, 2, :day),
        finished_at: DateTime.add(now, 3, :day)
      })

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?when=all")

    assert has_element?(lv, "#activity-#{done.id} td .badge", "Draft")
    refute has_element?(lv, "#activity-#{coming.id} td .badge", "Draft")
    refute has_element?(lv, "#activity_collection .marker-more", "Draft")
  end

  test "a coming activity's badge follows its title (#447)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    starts = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

    short =
      team
      |> activity_fixture(%{started_at: starts, finished_at: DateTime.add(starts, 2, :hour)})
      |> Ecto.Changeset.change(enough_at: 2)
      |> App.Repo.update!()

    plain =
      activity_fixture(team, %{started_at: starts, finished_at: DateTime.add(starts, 2, :hour)})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?when=all")

    assert has_element?(lv, "#activity-#{short.id}-need", "2 more needed")
    refute has_element?(lv, "#activity-#{plain.id}-need")
  end

  test "a team without chores has no Chores tile", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")

    assert has_element?(lv, "#activity-tile-event")
    refute has_element?(lv, "#activity-tile-chores")
  end

  test "Current shows a week either side of today, oldest first", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    days = fn n -> DateTime.add(now, n * 86_400, :second) end

    activity_fixture(team, %{
      title: "Rope rescue night",
      started_at: days.(-3),
      finished_at: days.(-3)
    })

    activity_fixture(team, %{title: "Board meeting", started_at: days.(4), finished_at: days.(4)})

    activity_fixture(team, %{
      title: "Rope tech weekend",
      started_at: days.(-10),
      finished_at: days.(1)
    })

    activity_fixture(team, %{title: "Old search", started_at: days.(-30), finished_at: days.(-30)})

    activity_fixture(team, %{title: "Next year", started_at: days.(300), finished_at: days.(300)})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities")

    lv |> form("#activity-filters", values: %{when: "current"}) |> render_change()

    assert has_element?(lv, "#activity_collection", "Rope rescue night")
    assert has_element?(lv, "#activity_collection", "Board meeting")
    assert has_element?(lv, "#activity_collection", "Rope tech weekend")
    refute has_element?(lv, "#activity_collection", "Old search")
    refute has_element?(lv, "#activity_collection", "Next year")

    html = lv |> element("#activity_collection") |> render()
    assert :binary.match(html, "Rope rescue night") < :binary.match(html, "Board meeting")
  end

  test "picking Future from the menu sorts it oldest first", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    days = fn n -> DateTime.add(now, n * 86_400, :second) end
    activity_fixture(team, %{title: "Next week", started_at: days.(7), finished_at: days.(7)})
    activity_fixture(team, %{title: "Next year", started_at: days.(300), finished_at: days.(300)})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?when=past&sort=date-")

    lv |> form("#activity-filters", values: %{when: "future"}) |> render_change()

    assert has_element?(lv, ~s|#activity-filters input[name="values[sort]"][value="date"]|)
    html = lv |> element("#activity_collection") |> render()
    assert :binary.match(html, "Next week") < :binary.match(html, "Next year")
  end

  test "the sorted column header says which way it sorts", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?sort=date")

    assert has_element?(lv, ~s|th[aria-sort="ascending"]|, "Date")
    # Newest first is where the list starts, so its link leaves the sort out.
    assert has_element?(lv, ~s|th[aria-sort] a[href="/teams/#{team.subdomain}/activities"]|)
  end

  test "the draft filter lists only activities D4H hasn't published", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{title: "Still a draft", is_published: false})
    activity_fixture(team, %{title: "Already published", is_published: true})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/activities?status=draft")

    assert has_element?(lv, "#activity_collection", "Still a draft")
    refute has_element?(lv, "#activity_collection", "Already published")
  end

  test "the kind switch counts each kind under the other filters and keeps the Kind column",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    activity_fixture(team, %{
      title: "Missing hiker",
      activity_kind: "incident",
      is_published: true
    })

    activity_fixture(team, %{title: "Rope night", activity_kind: "exercise", is_published: true})
    activity_fixture(team, %{title: "Old drill", activity_kind: "exercise", is_published: false})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?status=published")

    assert has_element?(lv, "#activity-tile-all[aria-current]", "2")
    assert has_element?(lv, "#activity-tile-incident", "1")
    assert has_element?(lv, "#activity-tile-exercise", "1")
    assert has_element?(lv, "#activity-tile-event", "0")
    assert has_element?(lv, "thead th", "Kind")

    lv |> element("#activity-tile-exercise") |> render_click()
    assert has_element?(lv, "#activity_collection", "Rope night")
    refute has_element?(lv, "#activity_collection", "Missing hiker")
    refute has_element?(lv, "#activity_collection", "Old drill")
    # A filter changes the rows, not the columns.
    assert has_element?(lv, "thead th", "Kind")
  end

  test "Enter in the search box filters the list (#333)", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{title: "Rope rescue night"})
    activity_fixture(team, %{title: "Board meeting"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")

    lv |> form("#activity-filters", values: %{q: "rope"}) |> render_submit()

    assert_patch(lv)
    assert has_element?(lv, "#activity_collection", "Rope rescue night")
    refute has_element?(lv, "#activity_collection", "Board meeting")
  end

  test "a filter that is on shows in blue, as a chip, and in the Filters count", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{title: "Still a draft", is_published: false})

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?status=draft")

    assert has_element?(lv, "#activity-filters .filter-menu.is-on", "Status")
    refute has_element?(lv, "#activity-filters .filter-menu.is-on", "Kind")
    assert has_element?(lv, "#activity-filters .filter-bar-count", "1")
    assert has_element?(lv, "#activity-filters-summary a", "Clear filters")

    lv |> element(".filter-bar-chips a", "Draft") |> render_click()

    assert_patch(lv, ~p"/teams/#{team}/activities")
    refute has_element?(lv, ".filter-bar-chips")
  end

  test "the count under the bar shows only while the search narrows the kind's tile",
       %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity_fixture(team, %{title: "Rope practice"})
    activity_fixture(team, %{title: "Navigation night"})

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")
    refute has_element?(lv, "#activity-filters-summary")

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?q=rope")

    assert has_element?(lv, "#activity-filters-summary strong", "1 activity")
  end

  test "Clear shows only while a filter or search is on, and says which", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")
    refute has_element?(lv, "#activity-filters-summary a", "Clear")

    {:ok, lv, _html} =
      conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?q=rope")

    lv |> element("#activity-filters-summary a", "Clear search") |> render_click()
    assert_patch(lv, ~p"/teams/#{team}/activities")
  end

  describe "Save as report (#784)" do
    test "team admins get it, with the list's picks; members don't", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities?activity=exercise")

      assert lv |> element("#activity-save-report") |> render() =~ "list=activities"
      assert lv |> element("#activity-save-report") |> render() =~ "activity=exercise"

      %{team: team, user: member_user} = member_with_login_fixture()

      {:ok, lv, _html} =
        build_conn() |> log_in_user(member_user) |> live(~p"/teams/#{team}/activities")

      refute has_element?(lv, "#activity-save-report")
      refute has_element?(lv, "#activity-add")
    end

    test "opens New report with the list's text, named for the picks", %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      activity_fixture(team, %{title: "Rope night", activity_kind: "exercise"})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/teams/#{team}/reports/new?list=activities&activity=exercise&q=rope")

      assert has_element?(lv, ~s|#report_name[value="Activities: Exercises, rope"]|)
      assert lv |> element("#report_query") |> render() =~ "switch activity"
      assert has_element?(lv, "#report-preview", "Rope night")
    end
  end

  test "a Records team has no Required fields filter", %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}/activities")

    assert has_element?(lv, "#activity-filters", "Hours tag")
    refute has_element?(lv, "#activity-filters", "Required fields")
  end
end
