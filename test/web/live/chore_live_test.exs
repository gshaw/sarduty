defmodule Web.ChoreLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()

    team =
      team
      |> Ecto.Changeset.change(
        member_logins: true,
        chores_enabled: true,
        d4h_access_key: "team-key"
      )
      |> Repo.update!()

    tag_fixture(team, "Primary Hours")
    category = chore_category_fixture(team)
    member = member_fixture(team, %{name: "Sam Rivera"})
    me = Repo.get_by!(App.Model.Member, team_id: team.id, email: user.email)
    %{conn: log_in_user(conn, user), team: team, member: member, me: me, category: category}
  end

  # D4H answering every write: event 900, and attendance row 701 for `member`. `fail`
  # answers a new event with a 500.
  defp stub_d4h(member, fail \\ false) do
    Req.Test.stub(App.Adapter.D4H, fn conn ->
      cond do
        fail and conn.method == "POST" and conn.request_path =~ ~r{/events$} ->
          conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"title" => "D4H is down"})

        conn.request_path =~ "/attendance" and conn.method == "GET" ->
          Req.Test.json(conn, %{"results" => [], "totalSize" => 0})

        conn.request_path =~ "/attendance" ->
          Req.Test.json(conn, %{
            "id" => 701,
            "activity" => %{"resourceType" => "Event", "id" => 900},
            "member" => %{"resourceType" => "Member", "id" => member.d4h_member_id},
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

  test "the page needs member logins", %{conn: conn, team: team} do
    team = team |> Ecto.Changeset.change(member_logins: false) |> Repo.update!()
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/chores") end
  end

  test "accepting the selected chores sends them to their month's activity; a cleared one stays waiting",
       ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    one = chore_fixture(member, category, %{date: ~D[2026-10-06], minutes: 60})
    two = chore_fixture(member, category, %{date: ~D[2026-10-19], description: "Truck 2 wash"})
    left = chore_fixture(member, category, %{description: "Hall floors"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    refute has_element?(lv, "#side-nav-chores .badge")
    assert has_element?(lv, "#chores-view-waiting[aria-current=page]", "3")
    assert has_element?(lv, "#accept", "Accept 3 chores")

    ids = [to_string(one.id), to_string(two.id)]
    lv |> form("#accept-form", %{chore_ids: ids}) |> render_change()
    assert has_element?(lv, "#accept", "Accept 2 chores")

    stub_d4h(member)
    html = lv |> form("#accept-form", %{chore_ids: ids}) |> render_submit()
    assert html =~ "Accepted 2 chores."
    assert html =~ "Chore activities are up to date."

    assert has_element?(lv, "#waiting-chores #chore-#{left.id}")
    refute has_element?(lv, "#waiting-chores #chore-#{one.id}")
    assert %{status: :accepted, decided_at: %DateTime{}} = Repo.get!(Chore, one.id)
    assert Repo.get!(Chore, left.id).status == :waiting

    [event] = Repo.all(ChoreEvent)
    assert %{month: ~D[2026-10-01], d4h_activity_id: 900, needs_send: false} = event
    refute has_element?(lv, "#chores-to-send")

    lv |> element("#chores-view-accepted", "2") |> render_click()
    assert_patch(lv, ~p"/teams/#{team}/chores?view=accepted")
    assert has_element?(lv, "#chore-event-#{event.id}", "October 2026")
    assert has_element?(lv, "#chore-event-#{event.id}", "2 hours")

    assert has_element?(
             lv,
             ~s(#chore-event-#{event.id} #chore-#{two.id} a[href="/teams/#{team.subdomain}/chores/#{two.id}"]),
             "Truck 2 wash"
           )
  end

  test "a send that does not go through offers Send changes, which sends again", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{date: ~D[2026-10-06]})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")

    stub_d4h(member, true)
    html = lv |> form("#accept-form", %{chore_ids: [to_string(chore.id)]}) |> render_submit()
    assert html =~ "Accepted 1 chore."
    assert html =~ "1 activity did not go through."
    assert has_element?(lv, "#chores-to-send", "1 activity is out of date.")

    stub_d4h(member)
    html = lv |> element("#send-changes") |> render_click()
    assert html =~ "Chore activities are up to date."
    refute has_element?(lv, "#chores-to-send")
    assert [%{needs_send: false, d4h_activity_id: 900}] = Repo.all(ChoreEvent)
  end

  test "a team admin declines a chore with a reason", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")
    assert has_element?(lv, "#chore-details", "Sam Rivera")

    html = lv |> form("#decline-form", decline: %{reason: ""}) |> render_submit()
    assert html =~ "Enter why, for the member"
    assert Repo.get!(Chore, chore.id).status == :waiting

    {:ok, _lv, html} =
      lv
      |> form("#decline-form", decline: %{reason: "The rental group cleans the hall."})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Declined Truck 1 wash."
    assert html =~ "The rental group cleans the hall."
    assert html =~ ~s(id="chore-#{chore.id}")

    assert %{status: :declined, decline_reason: "The rental group cleans the hall."} =
             Repo.get!(Chore, chore.id)
  end

  test "declining a sent chore takes it off its activity in D4H", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{date: ~D[2026-10-06]})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    stub_d4h(member)
    lv |> form("#accept-form", %{chore_ids: [to_string(chore.id)]}) |> render_submit()

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")

    {:ok, _lv, html} =
      lv
      |> form("#decline-form", decline: %{reason: "Standby is an activity."})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Declined Truck 1 wash."

    assert html =~ "Chore activities are up to date."
    assert %{status: :declined, chore_event_id: nil} = Repo.get!(Chore, chore.id)
  end

  test "a team admin changes an accepted chore to any date", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{status: :accepted})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}/edit")

    stub_d4h(member)

    {:ok, lv, html} =
      lv
      |> form("#chore-form", chore: %{date: "2025-01-15", time: "2h"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/chores?view=accepted")

    assert html =~ "Saved Truck 1 wash."

    assert html =~ "Chore activities are up to date."
    assert has_element?(lv, "#chore-#{chore.id}", "2 hours")
    assert %{status: :accepted, date: ~D[2025-01-15], minutes: 120} = Repo.get!(Chore, chore.id)
    assert [%{month: ~D[2025-01-01]}] = Repo.all(ChoreEvent)
  end

  test "a sent chore's page links its activity", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    activity = activity_fixture(team, %{title: "Chores: Equipment maintenance, October 2026"})

    event =
      Repo.insert!(%ChoreEvent{
        team_id: team.id,
        chore_category_id: category.id,
        month: ~D[2026-10-01],
        d4h_activity_id: activity.d4h_activity_id
      })

    chore = chore_fixture(member, category, %{status: :accepted, chore_event_id: event.id})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")
    assert has_element?(lv, "#chore-activity a", "Chores: Equipment maintenance, October 2026")
    assert has_element?(lv, "#chore-change")
    assert has_element?(lv, "#decline-form")
  end

  test "an unknown view is not found", %{conn: conn, team: team} do
    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/chores?view=everything")
    end
  end

  test "declined chores list with why", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx

    chore =
      chore_fixture(member, category, %{
        status: :declined,
        decided_at: ~U[2026-10-20 18:00:00.000000Z],
        decline_reason: "Standby is an activity."
      })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores?view=declined")
    assert has_element?(lv, "#chores-view-declined[aria-current=page]", "1")
    assert has_element?(lv, "#declined-chores #chore-#{chore.id}", "Standby is an activity.")
  end

  test "a decided chore names the team admin who decided it", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    named = App.AccountsFixtures.user_fixture()
    manager_fixture(team, %{email: named.email, name: "Avery Chen"})
    unnamed = App.AccountsFixtures.user_fixture()

    decided = fn user ->
      chore_fixture(member, category, %{
        status: :accepted,
        decided_at: ~U[2026-10-20 18:00:00.000000Z],
        decided_by_user_id: user.id
      })
    end

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{decided.(named).id}")
    assert has_element?(lv, "#chore-status", "Avery Chen")
    refute has_element?(lv, "#chore-status", named.email)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{decided.(unnamed).id}")
    assert has_element?(lv, "#chore-status", unnamed.email)
  end

  # Another team admin should accept a team admin's chores (#697).
  test "a team admin's own chores say Yours, start cleared, and take a box to accept", ctx do
    %{conn: conn, team: team, member: member, me: me, category: category} = ctx
    theirs = chore_fixture(member, category, %{date: ~D[2026-10-06]})
    mine = chore_fixture(me, category, %{date: ~D[2026-10-06], description: "Grant report"})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chore-yours-#{mine.id}", "Yours")
    refute has_element?(lv, "#chore-yours-#{theirs.id}")
    assert has_element?(lv, "#waiting-chores-select-#{theirs.id}[checked]")
    refute has_element?(lv, "#waiting-chores-select-#{mine.id}[checked]")
    assert has_element?(lv, ~s{#waiting-chores-select-#{mine.id}[data-select-all="skip"]})
    assert has_element?(lv, "#accept", "Accept 1 chore")
    refute has_element?(lv, "#accept-own")

    ids = [to_string(theirs.id), to_string(mine.id)]
    lv |> form("#accept-form", %{chore_ids: ids}) |> render_change()
    assert has_element?(lv, "#accept-own")
    assert has_element?(lv, "#accept[disabled]", "Accept 2 chores")

    # A stale page or a second tab doesn't get past the box.
    html = render_submit(lv, "accept", %{chore_ids: ids})
    assert html =~ "Select Accept my own chores to accept yours."
    assert Repo.get!(Chore, mine.id).status == :waiting
    assert Repo.get!(Chore, theirs.id).status == :waiting

    lv |> form("#accept-form", %{chore_ids: ids, own: "true"}) |> render_change()
    refute has_element?(lv, "#accept[disabled]")

    stub_d4h(member)
    lv |> form("#accept-form", %{chore_ids: ids, own: "true"}) |> render_submit()
    assert Repo.get!(Chore, mine.id).status == :accepted
    assert Repo.get!(Chore, theirs.id).status == :accepted
  end

  test "a team admin's own chore's page takes the box to accept it; declining doesn't", ctx do
    %{conn: conn, team: team, member: member, me: me, category: category} = ctx
    theirs = chore_fixture(member, category)
    mine = chore_fixture(me, category, %{date: ~D[2026-10-06]})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{theirs.id}")
    refute has_element?(lv, "#accept-own")
    refute has_element?(lv, "#chore-accept[disabled]")

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{mine.id}")
    assert has_element?(lv, "#accept-own")
    assert has_element?(lv, "#chore-accept[disabled]")
    assert has_element?(lv, "#chore-decline-button")

    assert render_submit(lv, "accept", %{}) =~ "Select Accept my own chores to accept yours."
    assert Repo.get!(Chore, mine.id).status == :waiting

    lv |> form("#accept-form", %{own: "true"}) |> render_change()
    refute has_element?(lv, "#chore-accept[disabled]")

    stub_d4h(me)

    {:ok, _lv, _html} =
      lv |> form("#accept-form", %{own: "true"}) |> render_submit() |> follow_redirect(conn)

    assert Repo.get!(Chore, mine.id).status == :accepted
  end

  test "another team's chore is not found", %{conn: conn, team: team} do
    other_team = team_fixture()
    chore = chore_fixture(member_fixture(other_team), chore_category_fixture(other_team))

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/teams/#{team}/chores/#{chore.id}") end
  end

  # Linda's case (#645): a team admin who is also a member looks under Chores to log one.
  test "a team admin who is a member logs their own chore from Chores", ctx do
    %{conn: conn, team: team, category: category} = ctx
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chores-view-yours")
    assert has_element?(lv, ~s{#chore-log[href="/teams/#{team.subdomain}/chores/new"]})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/new")
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    {:ok, lv, _html} =
      lv
      |> form("#chore-form",
        chore: %{
          date: Date.to_iso8601(today),
          time: "30m",
          chore_category_id: category.id,
          description: "Grant report"
        }
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/chores?view=yours")

    [chore] = Repo.all(Chore)
    assert chore.status == :waiting
    assert has_element?(lv, "#chore-#{chore.id}", "Grant report")
    assert has_element?(lv, "#chores-view-yours[aria-current]")
  end

  test "a SAR Duty admin who isn't on the team gets no Yours and no Log a chore", ctx do
    %{conn: conn, team: team} = ctx
    admin = App.AccountsFixtures.user_fixture() |> make_admin()
    conn = log_in_user(conn, admin)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#chores-view-waiting")
    refute has_element?(lv, "#chores-view-yours")
    refute has_element?(lv, "#chore-log")
    assert_raise Web.Status.NotFound, fn -> live(conn, ~p"/teams/#{team}/chores/new") end
  end
end
