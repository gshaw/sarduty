defmodule Web.ChoreLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Chore
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    team = team |> Ecto.Changeset.change(member_logins: true) |> Repo.update!()
    category = chore_category_fixture(team)
    member = member_fixture(team, %{name: "Sam Rivera"})
    %{conn: log_in_user(conn, user), team: team, member: member, category: category}
  end

  test "the page needs member logins", %{conn: conn, team: team} do
    team = team |> Ecto.Changeset.change(member_logins: false) |> Repo.update!()
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/chores") end
  end

  test "a team admin accepts the selected chores; a cleared one stays waiting", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    one = chore_fixture(member, category)
    two = chore_fixture(member, category, %{description: "Truck 2 wash"})
    left = chore_fixture(member, category, %{description: "Hall floors"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#side-nav-chores", "3")
    assert has_element?(lv, "#accept", "Accept 3 chores")

    ids = [to_string(one.id), to_string(two.id)]
    lv |> form("#accept-form", %{chore_ids: ids}) |> render_change()
    assert has_element?(lv, "#accept", "Accept 2 chores")

    lv |> form("#accept-form", %{chore_ids: ids}) |> render_submit()

    assert has_element?(lv, "#chore-#{left.id}")
    refute has_element?(lv, "#chore-#{one.id}")
    assert has_element?(lv, "#side-nav-chores", "1")
    assert %{status: :accepted, decided_at: %DateTime{}} = Repo.get!(Chore, one.id)
    assert Repo.get!(Chore, left.id).status == :waiting
  end

  test "a team admin declines a chore with a reason", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")
    assert has_element?(lv, "#chore-details", "Sam Rivera")

    html = lv |> form("#decline-form", decline: %{reason: ""}) |> render_submit()
    assert html =~ "Enter why, for the member"
    assert Repo.get!(Chore, chore.id).status == :waiting

    lv
    |> form("#decline-form", decline: %{reason: "The rental group cleans the hall."})
    |> render_submit()

    assert %{status: :declined, decline_reason: "The rental group cleans the hall."} =
             Repo.get!(Chore, chore.id)
  end

  test "a team admin changes an accepted chore to any date", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{status: :accepted})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}/edit")

    {:ok, _lv, _html} =
      lv
      |> form("#chore-form", chore: %{date: "2025-01-15", minutes: "120"})
      |> render_submit()
      |> follow_redirect(conn)

    assert %{status: :accepted, date: ~D[2025-01-15], minutes: 120} = Repo.get!(Chore, chore.id)
  end

  test "another team's chore is not found", %{conn: conn, team: team} do
    other_team = team_fixture()
    chore = chore_fixture(member_fixture(other_team), chore_category_fixture(other_team))

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/teams/#{team}/chores/#{chore.id}") end
  end
end
