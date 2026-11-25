defmodule Web.ChoreFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.Chore
  alias App.Repo

  # Log a chore for everyone who did it (#1102). No D4H stub: logging sends nothing.
  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    team =
      team
      |> Ecto.Changeset.change(member_logins: true, chores_enabled: true)
      |> Repo.update!()

    alex =
      App.Model.Member
      |> Repo.get_by!(team_id: team.id, email: user.email)
      |> Ecto.Changeset.change(name: "Alex Chen")
      |> Repo.update!()

    cameron = member_fixture(team, %{name: "Cameron Diaz", d4h_permission: 2})
    riley = member_fixture(team, %{name: "Riley Okafor"})

    %{
      conn: conn,
      admin: log_in_user(conn, user),
      team: team,
      alex: alex,
      cameron: cameron,
      riley: riley,
      category: chore_category_fixture(team, %{title: "Hall and gear"}),
      today: Service.Period.today(DateTime.utc_now(), team.timezone)
    }
  end

  defp as_cameron(%{conn: conn, cameron: cameron}),
    do: log_in_user(conn, App.AccountsFixtures.user_fixture(%{email: cameron.email}))

  defp add_others(lv) do
    if has_element?(lv, "#add-others"), do: lv |> element("#add-others") |> render_click()
    lv
  end

  defp pick(lv, member),
    do: lv |> add_others() |> form("#who-form", %{"member-id" => member.id}) |> render_change()

  defp chore_params(ctx, attrs \\ %{}) do
    Map.merge(
      %{
        date: Date.to_iso8601(Date.add(ctx.today, -1)),
        time: "3h",
        chore_category_id: ctx.category.id,
        description: "Gear day"
      },
      attrs
    )
  end

  test "a team admin logs one chore for two people, each their own, waiting", ctx do
    %{admin: conn, team: team, alex: alex, cameron: cameron} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")

    assert has_element?(lv, "#person-#{alex.id}", "Alex Chen")
    assert has_element?(lv, "#person-#{alex.id}-badge-you", "You")
    refute has_element?(lv, "#who-form")
    refute has_element?(lv, "#remove-person-#{alex.id}")
    assert has_element?(lv, "#chore-form label", "What you did")
    assert has_element?(lv, "#chore-save", "Log chore")
    assert has_element?(lv, "#chore-form", "Any date that has passed.")

    lv |> element("#add-others") |> render_click()
    assert has_element?(lv, "#who-form #person-#{alex.id}")
    assert has_element?(lv, "#remove-person-#{alex.id}")

    pick(lv, cameron)
    assert has_element?(lv, "#person-#{cameron.id}", "Cameron Diaz")
    refute has_element?(lv, "#person-#{cameron.id}-badge-you")
    refute has_element?(lv, ~s{#chore_people-select option[value="#{cameron.id}"]})
    assert has_element?(lv, "#chore-form label", "What they did")
    assert has_element?(lv, "#chore-save", "Log 2 chores")

    {:ok, _lv, html} =
      lv
      |> form("#chore-form", chore: chore_params(ctx))
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/chores")

    assert html =~ "Logged 2 chores."
    [one, two] = Chore |> Repo.all() |> Enum.sort_by(& &1.member_id)
    assert {one.member_id, two.member_id} == {alex.id, cameron.id}

    for chore <- [one, two] do
      assert %{status: :waiting, minutes: 180, description: "Gear day"} = chore
      assert chore.logged_by_member_id == alex.id
      assert chore.chore_category_id == ctx.category.id
      assert chore.date == Date.add(ctx.today, -1)
    end

    assert one.logged_together_id
    assert one.logged_together_id == two.logged_together_id
    refute_email_sent()
  end

  test "a team admin takes themselves off and logs for two others", ctx do
    %{admin: conn, team: team, alex: alex, cameron: cameron, riley: riley} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")

    lv |> add_others() |> element("#remove-person-#{alex.id}") |> render_click()
    refute has_element?(lv, "#person-#{alex.id}")
    pick(lv, cameron)
    pick(lv, riley)

    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert_redirect(lv, ~p"/teams/#{team}/chores")

    assert Chore |> Repo.all() |> Enum.map(& &1.member_id) |> Enum.sort() ==
             Enum.sort([cameron.id, riley.id])
  end

  test "a team admin's chore for themselves alone goes to Yours", ctx do
    {:ok, lv, _html} = live(ctx.admin, ~p"/teams/#{ctx.team}/chores/new")
    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert_redirect(lv, ~p"/teams/#{ctx.team}/chores?view=yours")
    assert [%{logged_together_id: nil}] = Repo.all(Chore)
  end

  test "saving with nobody listed asks who did it and saves nothing", ctx do
    %{admin: conn, team: team, alex: alex} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    lv |> add_others() |> element("#remove-person-#{alex.id}") |> render_click()
    assert has_element?(lv, "#who-form")
    assert has_element?(lv, "#chore-save", "Log chore")

    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert has_element?(lv, "#who-form .field-error", "Add who did it")
    assert has_element?(lv, ~s{#chore-errors a[href="#chore_people"]}, "Add who did it")
    assert Repo.all(Chore) == []

    pick(lv, ctx.cameron)
    refute has_element?(lv, "#who-form .field-error")
    refute has_element?(lv, ~s{#chore-errors a[href="#chore_people"]})
  end

  test "a member stays on the list, and logs for a teammate with no login", ctx do
    %{team: team, cameron: cameron, riley: riley, alex: alex} = ctx
    conn = as_cameron(ctx)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")

    assert has_element?(lv, "#person-#{cameron.id}-badge-you", "You")
    assert has_element?(lv, "#add-others")
    lv |> element("#add-others") |> render_click()
    refute has_element?(lv, "#remove-person-#{cameron.id}")
    assert has_element?(lv, "#chore-form", "In the last 60 days.")
    assert has_element?(lv, "#chore-form label", "What you did")

    # A stale page or a crafted event can't take them off.
    render_click(lv, "remove-person", %{"id" => "#{cameron.id}"})
    assert has_element?(lv, "#person-#{cameron.id}")

    pick(lv, riley)
    render_change(lv, "add-person", %{"member-id" => "#{riley.id}"})

    assert lv |> element("#who-did-it") |> render() |> String.split("Riley Okafor") |> length() ==
             2

    assert has_element?(lv, "#chore-form label", "What they did")
    assert has_element?(lv, "#chore-save", "Log 2 chores")

    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert_redirect(lv, ~p"/teams/#{team}/chores?view=yours")

    chores = Repo.all(Chore)
    assert chores |> Enum.map(& &1.member_id) |> Enum.sort() == Enum.sort([cameron.id, riley.id])
    assert Enum.all?(chores, &(&1.status == :waiting and &1.logged_by_member_id == cameron.id))
    refute Enum.any?(chores, &(&1.member_id == alex.id))
    refute_email_sent()
  end

  test "a save checks the list as it is now, not as the form opened", ctx do
    %{admin: conn, team: team, cameron: cameron, riley: riley} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    pick(lv, cameron)
    pick(lv, riley)

    riley |> Ecto.Changeset.change(d4h_status: "RETIRED") |> Repo.update!()
    html = lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert html =~ "Remove anyone who is not a current member."
    assert Repo.all(Chore) == []

    riley |> Ecto.Changeset.change(d4h_status: nil) |> Repo.update!()
    leavers = group_fixture(team, %{title: "Retiring"})
    group_member_fixture(leavers, riley)
    team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()
    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert Repo.all(Chore) == []

    team |> Ecto.Changeset.change(retiring_d4h_group_id: nil) |> Repo.update!()
    Repo.delete!(cameron)
    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert Repo.all(Chore) == []
  end

  test "the picker offers neither another team's member, a retiring one, nor one not a person",
       ctx do
    %{team: team} = ctx
    other_team_member = member_fixture(team_fixture())
    bot = member_fixture(team, %{name: "Gear Bot", not_a_person: true})
    leaver = member_fixture(team, %{name: "Lee Leaving"})
    leavers = group_fixture(team, %{title: "Retiring"})
    group_member_fixture(leavers, leaver)

    team
    |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
    |> Repo.update!()

    {:ok, lv, _html} = live(ctx.admin, ~p"/teams/#{team}/chores/new")

    for member <- [other_team_member, bot, leaver] do
      refute has_element?(lv, ~s{#chore_people-select option[value="#{member.id}"]})
      render_change(lv, "add-person", %{"member-id" => "#{member.id}"})
      refute has_element?(lv, "#person-#{member.id}")
    end
  end

  test "a member who is not a person logs a chore for themselves", %{conn: conn} = ctx do
    bot = member_fixture(ctx.team, %{name: "Gear Bot", not_a_person: true, d4h_permission: 2})
    conn = log_in_user(conn, App.AccountsFixtures.user_fixture(%{email: bot.email}))
    {:ok, lv, _html} = live(conn, ~p"/teams/#{ctx.team}/chores/new")
    assert has_element?(lv, "#person-#{bot.id}")

    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert [%{member_id: member_id}] = Repo.all(Chore)
    assert member_id == bot.id
  end

  test "a member logs from the last 60 days, a team admin any day that has passed", ctx do
    %{team: team, today: today} = ctx
    {:ok, member_lv, _html} = live(as_cameron(ctx), ~p"/teams/#{team}/chores/new")
    {:ok, admin_lv, _html} = live(ctx.admin, ~p"/teams/#{team}/chores/new")

    old = chore_params(ctx, %{date: today |> Date.add(-61) |> Date.to_iso8601()})

    assert member_lv |> form("#chore-form", chore: old) |> render_submit() =~
             "Enter a date in the last 60 days"

    tomorrow = chore_params(ctx, %{date: today |> Date.add(1) |> Date.to_iso8601()})

    assert member_lv |> form("#chore-form", chore: tomorrow) |> render_submit() =~
             "Enter a date that has passed"

    assert admin_lv |> form("#chore-form", chore: tomorrow) |> render_submit() =~
             "Enter a date that has passed"

    assert Repo.all(Chore) == []

    long_ago = chore_params(ctx, %{date: today |> Date.add(-200) |> Date.to_iso8601()})
    admin_lv |> form("#chore-form", chore: long_ago) |> render_submit()
    assert [%{status: :waiting, date: date}] = Repo.all(Chore)
    assert date == Date.add(today, -200)
  end

  test "Log and add another keeps Who did it, the date, and the category", ctx do
    %{admin: conn, team: team, cameron: cameron, category: category} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    pick(lv, cameron)

    html =
      lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit(%{another: "true"})

    assert html =~ "Logged 2 chores."
    assert html =~ "Add the next one."
    assert has_element?(lv, "#person-#{cameron.id}")
    assert has_element?(lv, "#person-#{ctx.alex.id}")
    assert has_element?(lv, "#chore-save", "Log 2 chores")
    assert has_element?(lv, ~s{#chore_date[value="#{Date.add(ctx.today, -1)}"]})

    assert has_element?(
             lv,
             ~s{#chore_chore_category_id-select option[value="#{category.id}"][selected]}
           )

    assert length(Repo.all(Chore)) == 2
  end

  test "Log and add another keeps the picker open once Add others was pressed", ctx do
    {:ok, lv, _html} = live(ctx.admin, ~p"/teams/#{ctx.team}/chores/new")
    lv |> element("#add-others") |> render_click()
    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit(%{another: "true"})
    assert has_element?(lv, "#who-form #person-#{ctx.alex.id}")
    refute has_element?(lv, "#add-others")
  end

  test "from a member's Chores tab, the list starts with that member and goes back there",
       ctx do
    %{admin: conn, team: team, alex: alex, cameron: cameron} = ctx
    tab = ~p"/teams/#{team}/members/#{cameron.id}/chores"
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new?member=#{cameron.id}")

    assert has_element?(lv, "#who-form #person-#{cameron.id}")
    refute has_element?(lv, "#person-#{alex.id}")
    assert has_element?(lv, ~s{#chore-log-cancel[href="#{tab}"]})

    lv |> form("#chore-form", chore: chore_params(ctx)) |> render_submit()
    assert_redirect(lv, tab)
    assert [%{member_id: member_id, logged_by_member_id: logger}] = Repo.all(Chore)
    assert {member_id, logger} == {cameron.id, alex.id}
  end

  test "?member= starts with the reader for another team's member, a retiring one, or a member",
       ctx do
    %{team: team, alex: alex, cameron: cameron, riley: riley} = ctx
    leaver = member_fixture(team)
    leavers = group_fixture(team, %{title: "Retiring"})
    group_member_fixture(leavers, leaver)

    team
    |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
    |> Repo.update!()

    for id <- [member_fixture(team_fixture()).id, leaver.id] do
      {:ok, lv, _html} = live(ctx.admin, ~p"/teams/#{team}/chores/new?member=#{id}")
      assert has_element?(lv, "#person-#{alex.id}")
      refute has_element?(lv, "#person-#{id}")
    end

    {:ok, lv, _html} = live(as_cameron(ctx), ~p"/teams/#{team}/chores/new?member=#{riley.id}")
    assert has_element?(lv, "#person-#{cameron.id}")
    refute has_element?(lv, "#person-#{riley.id}")
  end
end
