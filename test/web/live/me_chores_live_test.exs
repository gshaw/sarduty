defmodule Web.MeChoresLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Chore
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    category = chore_category_fixture(team)
    %{conn: log_in_user(conn, user), team: team, member: member, category: category}
  end

  test "a member logs a chore, and it waits for a team admin", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/chores")
    assert has_element?(lv, "#no-chores")
    assert has_element?(lv, "#side-nav-me[aria-current=page]")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/chores/new")
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    {:ok, lv, _html} =
      lv
      |> form("#chore-form",
        chore: %{
          date: Date.to_iso8601(today),
          minutes: "90",
          chore_category_id: category.id,
          description: "Truck 2 tire pressures"
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    [chore] = Chore.get_all_for_member(member)
    assert %{status: :waiting, minutes: 90, date: ^today} = chore
    assert has_element?(lv, "#chore-#{chore.id}", "Truck 2 tire pressures")
    assert has_element?(lv, "#chore-#{chore.id}", "Waiting")
    assert has_element?(lv, "#stat-waiting", "1h 30m")
  end

  test "a chore older than 60 days is refused", %{conn: conn, team: team, category: category} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/chores/new")
    old = team.timezone |> then(&Service.Period.today(DateTime.utc_now(), &1)) |> Date.add(-61)

    html =
      lv
      |> form("#chore-form",
        chore: %{date: old, minutes: "60", chore_category_id: category.id, description: "Old"}
      )
      |> render_submit()

    assert html =~ "Enter a date in the last 60 days"
  end

  test "a waiting chore can change; an accepted one cannot", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    waiting = chore_fixture(member, category)
    accepted = chore_fixture(member, category, %{status: :accepted, description: "Rope check"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/chores")
    assert has_element?(lv, "#chore-change-#{waiting.id}")
    refute has_element?(lv, "#chore-change-#{accepted.id}")
    refute has_element?(lv, "#chore-#{accepted.id}", "Waiting")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/chores/#{waiting.id}/edit")

    lv
    |> form("#chore-form", chore: %{minutes: "45"})
    |> render_submit()

    assert Repo.get!(Chore, waiting.id).minutes == 45

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/me/chores/#{accepted.id}/edit")
    end
  end

  test "a chore a team admin decides while the member's page is open does not change", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    waiting = chore_fixture(member, category, %{minutes: 60})

    declined =
      chore_fixture(member, category, %{status: :declined, decided_at: DateTime.utc_now()})

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/me/chores/#{waiting.id}/edit")
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/me/chores")

    for chore <- [waiting, declined],
        do: Repo.update!(Ecto.Changeset.change(chore, status: :accepted))

    {:ok, _lv, html} =
      edit
      |> form("#chore-form", chore: %{minutes: "45"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "This chore cannot change"
    assert Repo.get!(Chore, waiting.id).minutes == 60

    assert list |> element("#chore-delete-#{declined.id}") |> render_click() =~
             "cannot be deleted"

    assert Repo.get(Chore, declined.id)
  end

  test "a member sees why a chore was declined, and deletes it", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx

    declined =
      chore_fixture(member, category, %{
        status: :declined,
        decided_at: DateTime.utc_now(),
        decline_reason: "Log the generator check instead."
      })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/chores")
    assert has_element?(lv, "#chore-#{declined.id}", "Declined")
    assert has_element?(lv, "#chore-#{declined.id}", "Log the generator check instead.")

    lv |> element("#chore-delete-#{declined.id}") |> render_click()
    assert Repo.get(Chore, declined.id) == nil
  end

  test "another member's chore is not found", %{conn: conn, team: team, category: category} do
    other = chore_fixture(member_fixture(team), category)

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/me/chores/#{other.id}/edit")
    end
  end

  test "an archived category is not offered", %{conn: conn, team: team} do
    chore_category_fixture(team, %{title: "Old category", archived_at: DateTime.utc_now()})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/chores/new")
    refute render(lv) =~ "Old category"
  end
end
