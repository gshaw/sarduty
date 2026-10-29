defmodule Web.ChoreCollectionLiveTest do
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
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#no-chores")
    assert has_element?(lv, "#side-nav-chores[aria-current=page]")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    {:ok, lv, _html} =
      lv
      |> form("#chore-form",
        chore: %{
          date: Date.to_iso8601(today),
          time: "1.5h",
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

  test "Log and add another keeps the date and category for the next chore", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore_category_fixture(team, %{title: "Board work", description: "Meetings and minutes"})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")

    assert has_element?(
             lv,
             ~s{#chore_chore_category_id-select option[data-hint="Meetings and minutes"]}
           )

    refute has_element?(lv, "#chore-category-hint")

    yesterday =
      team.timezone |> then(&Service.Period.today(DateTime.utc_now(), &1)) |> Date.add(-1)

    lv |> element("#chore-date-yesterday") |> render_click()
    assert has_element?(lv, ~s{#chore_date[value="#{yesterday}"]})
    refute has_element?(lv, "#chore-form", "Enter what you did")

    lv |> form("#chore-form", chore: %{time: "2.5h"}) |> render_change()
    assert has_element?(lv, "#chore-time-read", "Reads as 2h 30m.")

    html =
      lv
      |> form("#chore-form",
        chore: %{time: "2.5h", chore_category_id: category.id, description: "Radio  programming"}
      )
      |> render_submit(%{another: "true"})

    assert html =~ "Logged Radio programming. Add the next one."
    assert [%{minutes: 150, date: ^yesterday}] = Chore.get_all_for_member(member)
    assert has_element?(lv, ~s{#chore_date[value="#{yesterday}"]})

    assert has_element?(
             lv,
             ~s{#chore_chore_category_id-select option[value="#{category.id}"][selected]}
           )

    refute has_element?(lv, "#chore-time-read")
  end

  test "a save with no category marks the categories as the error", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    refute has_element?(lv, "#chore_chore_category_id-combobox.is-invalid")

    lv |> form("#chore-form", chore: %{description: "Radio check", time: "1h"}) |> render_submit()
    assert has_element?(lv, "#chore_chore_category_id-combobox.is-invalid")
    assert has_element?(lv, "#chore-form .field-error", "Select a category")
  end

  test "a new chore starts on the category of the member's last one", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    board = chore_category_fixture(team, %{title: "Board work", description: "Meetings"})
    chore_fixture(member, category, %{date: Date.add(Date.utc_today(), -3)})
    chore_fixture(member, board, %{date: Date.add(Date.utc_today(), -9)})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    selected = ~s{#chore_chore_category_id-select option[value="#{board.id}"][selected]}
    assert has_element?(lv, selected)
    assert has_element?(lv, "#chore-category-hint", "Meetings")

    # Today, before anything is typed, keeps it.
    lv |> element("#chore-date-today") |> render_click()
    assert has_element?(lv, selected)
  end

  test "a time that reads as more than a day asks for minutes", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    html = lv |> form("#chore-form", chore: %{time: "30"}) |> render_change()
    assert html =~ "Enter 30m for minutes, or up to 24h"
    refute has_element?(lv, "#chore-time-read")
  end

  test "a chore older than 60 days is refused", %{conn: conn, team: team, category: category} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    old = team.timezone |> then(&Service.Period.today(DateTime.utc_now(), &1)) |> Date.add(-61)

    html =
      lv
      |> form("#chore-form",
        chore: %{date: old, time: "1h", chore_category_id: category.id, description: "Old"}
      )
      |> render_submit()

    assert html =~ "Enter a date in the last 60 days"
  end

  test "a waiting chore can change; an accepted one cannot", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    waiting = chore_fixture(member, category)
    accepted = chore_fixture(member, category, %{status: :accepted, description: "Rope check"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chore-change-#{waiting.id}")
    refute has_element?(lv, "#chore-change-#{accepted.id}")
    refute has_element?(lv, "#chore-#{accepted.id}", "Waiting")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{waiting.id}/edit")

    lv
    |> form("#chore-form", chore: %{time: "45m"})
    |> render_submit()

    assert Repo.get!(Chore, waiting.id).minutes == 45

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/chores/#{accepted.id}/edit")
    end
  end

  test "a chore a team admin decides while the member's page is open does not change", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    waiting = chore_fixture(member, category, %{minutes: 60})

    declined =
      chore_fixture(member, category, %{status: :declined, decided_at: DateTime.utc_now()})

    {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/chores/#{waiting.id}/edit")
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/chores")

    for chore <- [waiting, declined],
        do: chore |> Ecto.Changeset.change(status: :accepted) |> Repo.update!()

    {:ok, _lv, html} =
      edit
      |> form("#chore-form", chore: %{time: "45m"})
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

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chore-#{declined.id}", "Declined")
    assert has_element?(lv, "#chore-#{declined.id}", "Log the generator check instead.")

    lv |> element("#chore-delete-#{declined.id}") |> render_click()
    assert Repo.get(Chore, declined.id) == nil
  end

  test "another member's chore is not found", %{conn: conn, team: team, category: category} do
    other = chore_fixture(member_fixture(team), category)

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/teams/#{team}/chores/#{other.id}/edit")
    end
  end

  test "an archived category is not offered", %{conn: conn, team: team} do
    chore_category_fixture(team, %{title: "Old category", archived_at: DateTime.utc_now()})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    refute render(lv) =~ "Old category"
  end

  test "a member gets only Yours, with no team views", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    refute has_element?(lv, "#chores-switch")
    refute has_element?(lv, "#accept-form")

    for view <- ~w(waiting accepted declined) do
      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/chores?view=#{view}")
      end
    end
  end
end
