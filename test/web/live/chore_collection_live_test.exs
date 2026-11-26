defmodule Web.ChoreCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Model.Member
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
    assert has_element?(lv, "#chore_time-read", "Reads as 2h 30m.")

    html =
      lv
      |> form("#chore-form",
        chore: %{time: "2.5h", chore_category_id: category.id, description: "Radio  programming"}
      )
      |> render_submit(%{another: "true"})

    assert html =~ "Logged Radio programming."

    assert html =~ "Add the next one."
    assert [%{minutes: 150, date: ^yesterday}] = Chore.get_all_for_member(member)
    assert has_element?(lv, ~s{#chore_date[value="#{yesterday}"]})

    selected = ~s{#chore_chore_category_id-select option[value="#{category.id}"][selected]}
    assert has_element?(lv, selected)
    refute has_element?(lv, "#chore_time-read")

    # Today, before anything is typed, keeps it.
    lv |> element("#chore-date-today") |> render_click()
    assert has_element?(lv, selected)
  end

  test "a save with no category marks the categories as the error", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    refute has_element?(lv, "#chore_chore_category_id-combobox.is-invalid")

    lv |> form("#chore-form", chore: %{description: "Radio check", time: "1h"}) |> render_submit()
    assert has_element?(lv, "#chore_chore_category_id-combobox.is-invalid")
    assert has_element?(lv, "#chore-form .field-error", "Select a category")
  end

  # A default gets left as is, and the category decides primary or secondary hours.
  test "a new chore starts with no category, even after earlier ones", ctx do
    %{conn: conn, team: team, member: member} = ctx
    board = chore_category_fixture(team, %{title: "Board work", description: "Meetings"})
    chore_fixture(member, board)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")

    refute has_element?(
             lv,
             ~s{#chore_chore_category_id-select option[value="#{board.id}"][selected]}
           )

    refute has_element?(lv, "#chore_chore_category_id-select option[selected]:not([value=''])")
    refute has_element?(lv, "#chore-category-hint")
  end

  test "a bare number over 24 reads as minutes", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    lv |> form("#chore-form", chore: %{time: "30"}) |> render_change()
    assert has_element?(lv, "#chore_time-read", "30 min")
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

  describe "a chore someone else logged" do
    setup %{team: team} do
      alex = manager_fixture(team, %{name: "Alex Chen"})
      %{alex: alex, riley: member_fixture(team, %{name: "Riley Okafor"})}
    end

    test "says who logged it and how many others, and the member deletes it", ctx do
      %{conn: conn, team: team, member: member, alex: alex, riley: riley, category: category} =
        ctx

      category = category |> Ecto.Changeset.change(title: "Hall and gear") |> Repo.update!()
      together = %{logged_together_id: Ecto.UUID.generate(), logged_by_member_id: alex.id}
      mine = chore_fixture(member, category, together)
      chore_fixture(riley, category, together)
      long_ago = DateTime.utc_now() |> Service.Period.today(team.timezone) |> Date.add(-200)
      old = chore_fixture(member, category, %{logged_by_member_id: alex.id, date: long_ago})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")

      assert has_element?(
               lv,
               "#chore-#{mine.id}",
               "Hall and gear · With 1 other · Logged by Alex Chen"
             )

      assert has_element?(lv, "#chore-#{old.id}", "Hall and gear · Logged by Alex Chen")
      refute has_element?(lv, "#chore-#{old.id}", "With")

      {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/chores/#{old.id}/edit")

      assert edit |> form("#chore-form", chore: %{time: "2h"}) |> render_submit() =~
               "Enter a date in the last 60 days"

      edit |> element("#chore-delete") |> render_click()
      refute Repo.get(Chore, old.id)

      {:ok, edit, _html} = live(conn, ~p"/teams/#{team}/chores/#{mine.id}/edit")
      edit |> element("#chore-delete") |> render_click()
      refute Repo.get(Chore, mine.id)
    end
  end

  # A team admin filters Waiting, Accepted, and Declined (#1116).
  describe "filters" do
    setup %{team: team, category: hall} do
      %{user: user} = admin = admin_login_fixture(team)
      hall = hall |> Ecto.Changeset.change(title: "Hall and gear") |> Repo.update!()
      board = chore_category_fixture(team, %{title: "Board work"})

      people =
        for name <- ~w(Blake Cameron Dana Riley), do: member_fixture(team, %{name: "#{name} Lee"})

      [blake, cameron, dana, riley] = people
      today = Service.Period.today(DateTime.utc_now(), team.timezone)

      %{
        conn: log_in_user(build_conn(), user),
        me: admin.member,
        hall: hall,
        board: board,
        blake: blake,
        cameron: cameron,
        dana: dana,
        riley: riley,
        today: today
      }
    end

    defp admin_login_fixture(team) do
      user = App.AccountsFixtures.user_fixture()
      member = manager_fixture(team, %{email: user.email, name: "Alex Chen"})
      %{user: user, member: member}
    end

    defp log_together(logger, members, category, attrs \\ %{}) do
      together = %{logged_together_id: Ecto.UUID.generate(), logged_by_member_id: logger.id}
      Enum.map(members, &chore_fixture(&1, category, Map.merge(together, attrs)))
    end

    defp decided(member, category, status, attrs \\ %{}) do
      chore =
        chore_fixture(
          member,
          category,
          Map.merge(
            %{status: status, decided_at: DateTime.utc_now(), decline_reason: "No"},
            attrs
          )
        )

      :ok = ChoreEvent.place!(member.team_id)
      Repo.get!(Chore, chore.id)
    end

    defp option?(lv, field, value),
      do: has_element?(lv, ~s{#form_#{field} option[value="#{value}"]})

    defp combobox_option?(lv, member),
      do: has_element?(lv, ~s{#form_member-select option[value="#{member.id}"]})

    test "Category narrows Waiting, and each tile counts its view with it on", ctx do
      %{conn: conn, team: team, hall: hall, board: board, cameron: cameron, dana: dana} = ctx
      hall_chore = chore_fixture(cameron, hall)
      board_chore = chore_fixture(dana, board)
      decided(cameron, hall, :accepted)
      decided(dana, board, :accepted)
      decided(dana, board, :declined)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?category=#{hall.id}")
      assert has_element?(lv, "#waiting-chores #chore-#{hall_chore.id}")
      refute has_element?(lv, "#waiting-chores #chore-#{board_chore.id}")
      assert has_element?(lv, "#chores-view-waiting", "1")
      assert has_element?(lv, "#chores-view-accepted", "1")
      assert has_element?(lv, "#chores-view-declined", "0")
      assert has_element?(lv, "#accept", "Accept 1 chore")
      assert has_element?(lv, "#chore_filter_form .filter-menu.is-on #form_category")
      refute has_element?(lv, "#form_when")

      assert has_element?(
               lv,
               ~s{#chores-view-accepted[href="/teams/#{team.subdomain}/chores?view=accepted&category=#{hall.id}"]}
             )

      assert has_element?(
               lv,
               ~s{#chores-view-yours[href="/teams/#{team.subdomain}/chores?view=yours"]}
             )

      lv |> form("#chore_filter_form", form: %{category: board.id}) |> render_change()
      assert_patch(lv, ~p"/teams/#{team}/chores?category=#{board.id}")
      assert has_element?(lv, "#waiting-chores #chore-#{board_chore.id}")
      refute has_element?(lv, "#waiting-chores #chore-#{hall_chore.id}")
      assert has_element?(lv, "#chores-view-declined", "1")
    end

    test "Member lists who has a chore in the view, and a pick stays with nothing to show", ctx do
      %{conn: conn, team: team, hall: hall, board: board} = ctx
      %{blake: blake, cameron: cameron, dana: dana, riley: riley} = ctx
      chore_fixture(cameron, hall)
      chore_fixture(dana, board)
      decided(riley, hall, :accepted)
      decided(dana, hall, :declined)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
      assert combobox_option?(lv, cameron)
      assert combobox_option?(lv, dana)
      refute combobox_option?(lv, riley)
      refute combobox_option?(lv, blake)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?category=#{hall.id}")
      assert combobox_option?(lv, cameron)
      refute combobox_option?(lv, dana)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=accepted")
      assert combobox_option?(lv, riley)
      refute combobox_option?(lv, cameron)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=declined&member=#{cameron.id}")
      assert combobox_option?(lv, cameron)
      assert has_element?(lv, "#no-matching-chores", "No chores match")

      assert has_element?(
               lv,
               "#no-matching-chores",
               "Change the filters, or select All under Period."
             )

      refute has_element?(lv, "#no-declined-chores")
    end

    test "with no filters and no chores, the empty states are today's", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/chores")
      assert has_element?(lv, "#no-waiting-chores")
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/chores?view=accepted")
      assert has_element?(lv, "#no-chore-events")
    end

    test "Waiting with nothing to show says so, and has no Period", ctx do
      %{conn: conn, team: team, hall: hall, board: board, dana: dana} = ctx
      chore_fixture(dana, board)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?category=#{hall.id}&when=2025")
      assert has_element?(lv, "#no-matching-chores", "Change the filters.")
      refute render(lv) =~ "select All under Period"

      assert has_element?(
               lv,
               ~s{#chores-view-accepted[href="/teams/#{team.subdomain}/chores?view=accepted&category=#{hall.id}"]}
             )
    end

    test "Accepted opens on the last 12 months, whole months, and a year or All picks others",
         ctx do
      %{conn: conn, team: team, hall: hall, cameron: cameron, today: today} = ctx
      recent = decided(cameron, hall, :accepted)
      first_month = today |> Date.beginning_of_month() |> Date.shift(month: -11)
      edge = decided(cameron, hall, :accepted, %{date: first_month})
      old_date = Date.shift(first_month, month: -2)
      old = decided(cameron, hall, :accepted, %{date: old_date})

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=accepted")
      assert has_element?(lv, "#chore-#{recent.id}")
      assert has_element?(lv, "#chore-#{edge.id}")
      refute has_element?(lv, "#chore-#{old.id}")
      assert has_element?(lv, "#chores-view-accepted", "2")
      refute has_element?(lv, "#chore_filter_form .filter-menu.is-on")
      assert option?(lv, "when", "12mo")
      assert option?(lv, "when", "#{old_date.year}")
      assert option?(lv, "when", "all")

      lv |> form("#chore_filter_form", form: %{when: "all"}) |> render_change()
      assert_patch(lv, ~p"/teams/#{team}/chores?view=accepted&when=all")
      assert has_element?(lv, "#chore-#{old.id}")
      assert has_element?(lv, "#chore_filter_form .filter-menu.is-on")

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=accepted&when=#{old_date.year}")
      assert has_element?(lv, "#chore-#{old.id}")
      refute has_element?(lv, "#chore-#{recent.id}")

      assert has_element?(
               lv,
               ~s{#chores-view-declined[href="/teams/#{team.subdomain}/chores?view=declined&when=#{old_date.year}"]}
             )

      assert has_element?(lv, ~s{#chores-view-waiting[href="/teams/#{team.subdomain}/chores"]})
    end

    test "a year with no chores left stays picked under Period", %{conn: conn, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=accepted&when=2020")
      assert has_element?(lv, ~s{#form_when option[value="2020"][selected]})
    end

    test "submitting the same filters keeps the rows checked", ctx do
      %{conn: conn, team: team, hall: hall, cameron: cameron, dana: dana} = ctx
      kept = chore_fixture(cameron, hall)
      chore_fixture(dana, hall)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?category=#{hall.id}")
      lv |> form("#accept-form", %{chore_ids: ["#{kept.id}"]}) |> render_change()
      assert has_element?(lv, "#accept", "Accept 1 chore")

      lv |> form("#chore_filter_form", form: %{category: hall.id}) |> render_submit()
      assert has_element?(lv, "#accept", "Accept 1 chore")
    end

    test "a month is mo: when=3m is not found", %{conn: conn, team: team} do
      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/chores?view=accepted&when=3m")
      end
    end

    test "another team's category or member is not found", %{conn: conn, team: team} do
      other = team_fixture()
      category = chore_category_fixture(other)
      member = member_fixture(other)

      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/chores?category=#{category.id}")
      end

      assert_raise Web.Status.NotFound, fn ->
        live(conn, ~p"/teams/#{team}/chores?view=accepted&member=#{member.id}")
      end
    end

    test "Accepted shows only the activities with a chore that matches, with whole totals", ctx do
      %{conn: conn, team: team, hall: hall, board: board, blake: blake, cameron: cameron} = ctx
      mine = decided(cameron, hall, :accepted, %{minutes: 90})
      theirs = decided(blake, hall, :accepted, %{minutes: 60})
      board_chore = decided(blake, board, :accepted)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=accepted&member=#{cameron.id}")
      assert has_element?(lv, "#chore-#{mine.id}")
      refute has_element?(lv, "#chore-#{theirs.id}")
      refute has_element?(lv, "#chore-event-#{board_chore.chore_event_id}")

      assert has_element?(
               lv,
               "#chore-event-#{mine.chore_event_id}",
               "Activity total: 2 members · 2h 30m"
             )

      assert has_element?(lv, "#chores-view-accepted", "1")
    end

    test "with a member picked, a group row shows whole, in bold, and Accept takes it whole",
         ctx do
      %{conn: conn, team: team, hall: hall, board: board, me: me} = ctx
      %{blake: blake, cameron: cameron, riley: riley, dana: dana} = ctx
      group = log_together(me, [blake, cameron, riley], hall)
      alone = chore_fixture(cameron, board)
      hidden = chore_fixture(dana, hall)
      first = Enum.min_by(group, &Repo.get!(Member, &1.member_id).name)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?member=#{cameron.id}")
      assert has_element?(lv, "#waiting-chores #chore-#{first.id}")
      refute has_element?(lv, "#waiting-chores #chore-#{hidden.id}")
      cameron_chore = Enum.find(group, &(&1.member_id == cameron.id))
      assert has_element?(lv, "#chore-#{cameron_chore.id}-name.font-semibold")
      refute has_element?(lv, "#chore-#{first.id}-name.font-semibold")
      assert has_element?(lv, "#chores-view-waiting", "4")
      assert has_element?(lv, "#accept", "Accept 4 chores")

      lv |> form("#accept-form", %{chore_ids: ["#{alone.id}"]}) |> render_change()
      assert has_element?(lv, "#accept", "Accept 1 chore")

      stub_d4h()
      ids = ["#{first.id}", "#{hidden.id}"]

      assert lv |> form("#accept-form") |> render_submit(%{chore_ids: ids}) =~
               "Accepted 3 chores."

      assert Enum.all?(group, &(Repo.get!(Chore, &1.id).status == :accepted))
      assert Repo.get!(Chore, alone.id).status == :waiting
      assert Repo.get!(Chore, hidden.id).status == :waiting
    end

    test "a group with the reader on it starts unchecked and takes the box, with filters on",
         ctx do
      %{conn: conn, team: team, hall: hall, me: me, cameron: cameron, dana: dana} = ctx
      group = log_together(me, [me, cameron, dana], hall)
      other = chore_fixture(cameron, hall, %{description: "Radio check"})
      hidden = chore_fixture(dana, ctx.board)
      first = Enum.find(group, &(&1.member_id == me.id))

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?member=#{cameron.id}")
      refute has_element?(lv, "#waiting-chores-select-#{first.id}[checked]")
      assert has_element?(lv, "#waiting-chores-select-#{other.id}[checked]")
      assert has_element?(lv, "#accept", "Accept 1 chore")

      lv |> form("#accept-form", %{chore_ids: ["#{first.id}"]}) |> render_change()
      assert has_element?(lv, "#accept[disabled]", "Accept 3 chores")

      ids = ["#{first.id}", "#{hidden.id}"]

      assert lv |> form("#accept-form") |> render_submit(%{chore_ids: ids}) =~
               "another team admin"

      assert Enum.all?(group, &(Repo.get!(Chore, &1.id).status == :waiting))

      stub_d4h()
      lv |> form("#accept-form") |> render_submit(%{chore_ids: ids, own: "true"})
      assert Enum.all?(group, &(Repo.get!(Chore, &1.id).status == :accepted))
      assert Repo.get!(Chore, other.id).status == :waiting
      assert Repo.get!(Chore, hidden.id).status == :waiting
    end

    defp stub_d4h do
      Req.Test.stub(App.Adapter.D4H, fn conn ->
        cond do
          conn.request_path =~ "/attendance" and conn.method == "GET" ->
            Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

          conn.request_path =~ "/attendance" ->
            Req.Test.json(conn, %{
              "id" => System.unique_integer([:positive]),
              "activity" => %{"resourceType" => "Event", "id" => 900},
              "member" => %{"resourceType" => "Member", "id" => 1},
              "status" => "ATTENDING",
              "startsAt" => "2026-10-06T07:00:00Z",
              "endsAt" => "2026-10-06T08:30:00Z"
            })

          true ->
            Req.Test.json(conn, %{
              "id" => 900,
              "resourceType" => "Event",
              "owner" => %{"resourceType" => "Team", "id" => 1},
              "published" => false,
              "startsAt" => "2026-10-06T07:00:00Z",
              "endsAt" => "2026-10-06T08:30:00Z",
              "tags" => []
            })
        end
      end)
    end
  end
end
