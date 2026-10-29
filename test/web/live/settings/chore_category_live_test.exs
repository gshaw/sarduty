defmodule Web.Settings.ChoreCategoryLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChoreCategory
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    team =
      team |> Ecto.Changeset.change(member_logins: true, chores_enabled: true) |> Repo.update!()

    %{conn: log_in_user(conn, user), team: team}
  end

  test "doesn't exist, or show in the side navigation, while member logins are off", ctx do
    team = ctx.team |> Ecto.Changeset.change(member_logins: false) |> Repo.update!()

    assert_raise Web.Status.NotFound, fn ->
      live(ctx.conn, ~p"/teams/#{team}/settings/chore-categories")
    end

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{team}/settings")
    refute has_element?(lv, ".tabs a", "Chore categories")
  end

  test "a team admin adds a category with its hours and other tags", %{conn: conn, team: team} do
    tag_fixture(team, "Primary Hours")
    chores = tag_fixture(team, "Chores")
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/chore-categories")
    assert has_element?(lv, "#no-chore-categories")
    assert has_element?(lv, ".tabs a[aria-current=page]", "Chore categories")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/chore-categories/new")
    lv |> form("#tag-search-form", tag_q: "cho") |> render_change()
    refute has_element?(lv, "#tag-search-results", "Primary Hours")
    lv |> element("#tag-add-#{chores.id}") |> render_click()
    assert has_element?(lv, "#chore-category-tags", "Chores")

    {:ok, lv, _html} =
      lv
      |> form("#chore-category-form",
        category: %{
          title: "Equipment maintenance",
          description: "Trucks, radios, and the yard",
          hours: "primary"
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert has_element?(lv, "#chore-categories", "Equipment maintenance")
    [category] = ChoreCategory.get_all(team.id)
    assert %{hours: :primary, description: "Trucks, radios, and the yard"} = category
    assert category |> ChoreCategory.tags() |> Enum.map(& &1.title) == ["Chores"]
  end

  test "a category needs a name and its hours", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/chore-categories/new")

    html = lv |> form("#chore-category-form", category: %{title: " "}) |> render_submit()

    assert html =~ "Enter a name for the category"
    assert html =~ "Select which hours the chores count for"
    assert ChoreCategory.get_all(team.id) == []
  end

  test "archiving takes a category off members' choices, and restoring puts it back", ctx do
    %{conn: conn, team: team} = ctx

    category =
      Repo.insert!(%ChoreCategory{team_id: team.id, title: "Training", hours: :secondary})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/chore-categories/#{category.id}")

    {:ok, lv, _html} =
      lv |> element("#chore-category-archive") |> render_click() |> follow_redirect(conn)

    assert has_element?(lv, "#chore-category-#{category.id}", "Archived")
    assert ChoreCategory.get_open(team.id) == []

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/chore-categories/#{category.id}")
    lv |> element("#chore-category-restore") |> render_click()
    assert [%{id: id}] = ChoreCategory.get_open(team.id)
    assert id == category.id
  end

  test "another team's category is not found", %{conn: conn, team: team} do
    other = team_fixture()
    category = Repo.insert!(%ChoreCategory{team_id: other.id, title: "Other", hours: :primary})

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/settings/chore-categories/#{category.id}")
    end
  end
end
