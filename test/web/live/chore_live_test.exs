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
    %{conn: log_in_user(conn, user), team: team, member: member, category: category}
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
    assert has_element?(lv, "#side-nav-chores", "3")
    assert has_element?(lv, "#accept", "Accept 3 chores")
    assert has_element?(lv, "#no-chore-events")

    ids = [to_string(one.id), to_string(two.id)]
    lv |> form("#accept-form", %{chore_ids: ids}) |> render_change()
    assert has_element?(lv, "#accept", "Accept 2 chores")

    stub_d4h(member)
    html = lv |> form("#accept-form", %{chore_ids: ids}) |> render_submit()
    assert html =~ "Accepted 2 chores. D4H is up to date."

    assert has_element?(lv, "#waiting-chores #chore-#{left.id}")
    refute has_element?(lv, "#waiting-chores #chore-#{one.id}")
    assert has_element?(lv, "#side-nav-chores", "1")
    assert %{status: :accepted, decided_at: %DateTime{}} = Repo.get!(Chore, one.id)
    assert Repo.get!(Chore, left.id).status == :waiting

    [event] = Repo.all(ChoreEvent)
    assert %{month: ~D[2026-10-01], d4h_activity_id: 900, needs_send: false} = event
    assert has_element?(lv, "#chore-event-#{event.id}", "October 2026")
    assert has_element?(lv, "#chore-event-#{event.id}", "2 hours")
    refute has_element?(lv, "#chores-to-send")
  end

  test "a send that does not go through offers Send changes, which sends again", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{date: ~D[2026-10-06]})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")

    stub_d4h(member, true)
    html = lv |> form("#accept-form", %{chore_ids: [to_string(chore.id)]}) |> render_submit()
    assert html =~ "Accepted 1 chore. 1 activity did not go through to D4H."
    assert has_element?(lv, "#chores-to-send", "1 activity in D4H is out of date.")

    stub_d4h(member)
    html = lv |> element("#send-changes") |> render_click()
    assert html =~ "D4H is up to date."
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

    assert html =~ "Declined Truck 1 wash. D4H is up to date."
    assert %{status: :declined, chore_event_id: nil} = Repo.get!(Chore, chore.id)
  end

  test "a team admin changes an accepted chore to any date", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    chore = chore_fixture(member, category, %{status: :accepted})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}/edit")

    stub_d4h(member)

    {:ok, _lv, html} =
      lv
      |> form("#chore-form", chore: %{date: "2025-01-15", minutes: "120"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Saved Truck 1 wash. D4H is up to date."
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

  test "another team's chore is not found", %{conn: conn, team: team} do
    other_team = team_fixture()
    chore = chore_fixture(member_fixture(other_team), chore_category_fixture(other_team))

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/teams/#{team}/chores/#{chore.id}") end
  end
end
