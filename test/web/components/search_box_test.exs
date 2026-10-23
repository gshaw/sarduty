defmodule Web.Components.SearchBoxTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias Web.Components.Search

  describe "a team admin" do
    setup %{conn: conn} do
      %{user: user, team: team} = user_with_team_fixture()
      %{conn: log_in_user(conn, user), team: team}
    end

    test "every team page has the search, telling what it finds", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members")

      assert has_element?(lv, "#search-open[aria-label=Search]")
      assert has_element?(lv, "#search-input[role=combobox]")

      assert has_element?(
               lv,
               "#search-hint",
               "Find members, activities, equipment, qualifications, groups, endorsements, templates, and pages by name, D4H number, or barcode."
             )
    end

    test "typing lists matches in groups, each opening its page", %{conn: conn, team: team} do
      member = member_fixture(team, %{name: "Alice Wong", position: "Team leader"})

      activity =
        activity_fixture(team, %{
          title: "Alice Lake missing hiker",
          ref_id: "00403",
          activity_kind: "incident"
        })

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      lv |> form("#search-form", %{q: "alice"}) |> render_change()

      assert has_element?(lv, "#search-group-member h2", "Members")

      assert has_element?(
               lv,
               ~s{#search-hit-member-#{member.id}[href="/teams/#{team.subdomain}/members/#{member.id}"]}
             )

      assert has_element?(lv, "#search-hit-member-#{member.id} b", "Alice")
      assert has_element?(lv, "#search-hit-member-#{member.id}", "Team leader")
      assert has_element?(lv, "#search-hit-activity-#{activity.id} .marker-incident", "Incident")
      assert has_element?(lv, "#search-hit-activity-#{activity.id}", "#00403")
      refute has_element?(lv, "#search-hint")
    end

    test "says when nothing matches", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      lv |> form("#search-form", %{q: "cheakamus bridge"}) |> render_change()

      assert has_element?(lv, "#search-none h2", "Nothing matches “cheakamus bridge”")
      assert has_element?(lv, "#search-none", "SAR Duty refreshes from D4H every 10 minutes")
    end

    test "Enter opens the best result", %{conn: conn, team: team} do
      activity = activity_fixture(team, %{title: "Rope night", ref_id: "02193"})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      path = ~p"/teams/#{team}/activities/#{activity.id}"

      assert {:error, {:live_redirect, %{to: ^path}}} =
               lv |> form("#search-form", %{q: "2193"}) |> render_submit()
    end

    test "a one-word search with more than 5 matches links to the list", %{conn: conn, team: team} do
      for n <- 1..6, do: member_fixture(team, %{name: "Sam #{n}"})
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}")

      lv |> form("#search-form", %{q: "sam"}) |> render_change()

      assert has_element?(
               lv,
               ~s{#search-more-member[href="/teams/#{team.subdomain}/members?q=sam&standing=all"]},
               "All members with “sam”"
             )

      lv |> form("#search-form", %{q: "sam 1"}) |> render_change()
      refute has_element?(lv, "#search-more-member")
    end
  end

  test "a member finds activities and pages only", %{conn: conn} do
    %{team: team, user: user} = member_with_login_fixture()
    member_fixture(team, %{name: "Rope Rider"})
    activity = activity_fixture(team, %{title: "Rope night"})
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/teams/#{team}")

    assert has_element?(lv, "#search-hint", "Find activities and pages by name or D4H number.")

    lv |> form("#search-form", %{q: "rope"}) |> render_change()
    assert has_element?(lv, "#search-hit-activity-#{activity.id}")
    refute has_element?(lv, "#search-group-member")
  end

  test "pages outside a team have no search", %{conn: conn} do
    %{user: user} = user_with_team_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")
    refute has_element?(lv, "#search")
  end

  describe "highlight/2" do
    test "bolds where each word first appears" do
      assert Search.highlight("Navigation day, Alice Lake", ["alice", "lake"]) ==
               [{false, "Navigation day, "}, {true, "Alice"}, {false, " "}, {true, "Lake"}]
    end

    test "joins overlapping words and leaves titles without them plain" do
      assert Search.highlight("Rope rescue", ["rop", "rope"]) == [
               {true, "Rope"},
               {false, " rescue"}
             ]

      assert Search.highlight("Rope", ["02193"]) == [{false, "Rope"}]
    end
  end
end
