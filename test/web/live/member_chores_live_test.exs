defmodule Web.MemberChoresLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Repo

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
    category = chore_category_fixture(team, %{title: "Hall and gear"})
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    %{
      conn: conn,
      admin: log_in_user(conn, user),
      team: team,
      alex: alex,
      cameron: cameron,
      category: category,
      today: today
    }
  end

  defp chores(ctx) do
    %{cameron: cameron, alex: alex, category: category, today: today} = ctx
    day = Date.new!(today.year, 1, 1)
    riley = member_fixture(ctx.team, %{name: "Riley Okafor"})
    together = %{logged_together_id: Ecto.UUID.generate(), logged_by_member_id: alex.id}

    %{
      accepted: chore_fixture(cameron, category, %{status: :accepted, minutes: 180, date: day}),
      waiting: chore_fixture(cameron, category, Map.merge(together, %{minutes: 360})),
      declined: chore_fixture(cameron, category, %{status: :declined, description: "Radio"}),
      last_year: chore_fixture(cameron, category, %{status: :accepted, date: Date.add(day, -1)}),
      riley: chore_fixture(riley, category, together)
    }
  end

  test "a team admin sees every chore, with its tag and line, and logs one", ctx do
    %{admin: conn, team: team, cameron: cameron, today: today} = ctx
    c = chores(ctx)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{cameron.id}")

    assert has_element?(
             lv,
             ~s{a[href="/teams/#{team.subdomain}/members/#{cameron.id}/chores"]},
             "Chores"
           )

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{cameron.id}/chores")

    assert has_element?(
             lv,
             "#member-chores-summary",
             "3 hours accepted in #{today.year}, 6 hours waiting"
           )

    assert has_element?(lv, "#chore-#{c.waiting.id}-status", "Waiting")
    assert has_element?(lv, "#chore-#{c.declined.id}-status", "Declined")
    refute has_element?(lv, "#chore-#{c.accepted.id}-status")
    assert has_element?(lv, "#chore-#{c.last_year.id}")
    refute has_element?(lv, "#chore-#{c.riley.id}")

    assert has_element?(
             lv,
             ~s{#chore-#{c.waiting.id} a[href="/teams/#{team.subdomain}/chores/#{c.waiting.id}"]}
           )

    assert has_element?(
             lv,
             "#chore-#{c.waiting.id}",
             "Hall and gear · With 1 other · Logged by Alex Chen"
           )

    assert has_element?(
             lv,
             ~s{#member-chore-log[href="/teams/#{team.subdomain}/chores/new?member=#{cameron.id}"]}
           )
  end

  test "a member sees only accepted chores, not linked, and no Log a chore", ctx do
    %{team: team, cameron: cameron, today: today} = ctx
    c = chores(ctx)

    member_conn =
      log_in_user(ctx.conn, App.AccountsFixtures.user_fixture(%{email: cameron.email}))

    riley_id = c.riley.member_id

    riley_user =
      App.AccountsFixtures.user_fixture(%{email: Repo.get!(App.Model.Member, riley_id).email})

    {:ok, lv, _html} =
      ctx.conn |> log_in_user(riley_user) |> live(~p"/teams/#{team}/members/#{cameron.id}/chores")

    assert has_element?(lv, "#member-chores-summary", "3 hours accepted in #{today.year}")
    refute has_element?(lv, "#member-chores-summary", "waiting")
    assert has_element?(lv, "#chore-#{c.accepted.id}")
    refute has_element?(lv, "#chore-#{c.accepted.id} a")
    refute has_element?(lv, "#chore-#{c.waiting.id}")
    refute has_element?(lv, "#chore-#{c.declined.id}")
    refute has_element?(lv, "#member-chore-log")

    assert {:error, {:live_redirect, %{to: to}}} =
             live(member_conn, ~p"/teams/#{team}/members/#{cameron.id}/chores")

    assert to == ~p"/teams/#{team}/me"
  end

  test "with nothing accepted this year, the line starts at 0 hours", ctx do
    %{admin: conn, team: team, cameron: cameron, today: today} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{cameron.id}/chores")
    assert has_element?(lv, "#member-chores-summary", "0 hours accepted in #{today.year}")
    assert has_element?(lv, "#no-member-chores", "No chores yet")
  end

  test "a chore Alex logged for Cameron alone says who logged it, with no With", ctx do
    %{admin: conn, team: team, alex: alex, cameron: cameron, category: category} = ctx
    chore = chore_fixture(cameron, category, %{logged_by_member_id: alex.id})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{cameron.id}/chores")
    assert has_element?(lv, "#chore-#{chore.id}", "Hall and gear · Logged by Alex Chen")
    refute has_element?(lv, "#chore-#{chore.id}", "With")

    member_conn =
      log_in_user(ctx.conn, App.AccountsFixtures.user_fixture(%{email: cameron.email}))

    {:ok, lv, _html} = live(member_conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chore-#{chore.id}", "Hall and gear · Logged by Alex Chen")
    refute has_element?(lv, "#chore-#{chore.id}", "With")
  end

  test "on a team with chores off, there is no tab and the page is not found", ctx do
    %{admin: conn, team: team, cameron: cameron} = ctx
    team |> Ecto.Changeset.change(chores_enabled: false) |> Repo.update!()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{cameron.id}")
    refute has_element?(lv, ~s{a[href="/teams/#{team.subdomain}/members/#{cameron.id}/chores"]})

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/members/#{cameron.id}/chores")
    end
  end
end
