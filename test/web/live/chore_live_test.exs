defmodule Web.ChoreLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Chore
  alias App.Model.ChoreEvent
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

    assert has_element?(lv, "#waiting-chores #chore-#{left.id}")
    refute has_element?(lv, "#waiting-chores #chore-#{one.id}")
    assert has_element?(lv, "#ready-chores #chore-#{one.id}")
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

  test "accepted chores wait to be sent, then show in D4H", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx
    team = team |> Ecto.Changeset.change(d4h_access_key: "team-key") |> Repo.update!()
    tag_fixture(team, "Primary Hours")
    chore = chore_fixture(member, category, %{date: ~D[2026-10-06], minutes: 90})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores")
    assert has_element?(lv, "#no-ready-chores")
    assert has_element?(lv, "#no-chore-events")

    lv |> form("#accept-form", %{chore_ids: [to_string(chore.id)]}) |> render_submit()
    assert has_element?(lv, "#ready-chores #chore-#{chore.id}")
    assert has_element?(lv, "#send", "Send 1 chore")

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      event = %{
        "id" => 900,
        "resourceType" => "Event",
        "owner" => %{"resourceType" => "Team", "id" => 1},
        "startsAt" => "2026-10-06T07:00:00Z",
        "endsAt" => "2026-10-06T08:30:00Z",
        "tags" => []
      }

      if conn.request_path =~ "/attendance",
        do:
          Req.Test.json(conn, %{
            "id" => 701,
            "activity" => %{"resourceType" => "Event", "id" => 900},
            "member" => %{"resourceType" => "Member", "id" => member.d4h_member_id},
            "status" => "ATTENDING",
            "startsAt" => "2026-10-06T07:00:00Z",
            "endsAt" => "2026-10-06T08:30:00Z"
          }),
        else: Req.Test.json(conn, event)
    end)

    lv |> form("#send-form", %{send_ids: [to_string(chore.id)]}) |> render_submit()

    assert render(lv) =~ "Sent 1 chore to D4H as 1 activity."
    event_id = Repo.get!(Chore, chore.id).chore_event_id
    assert has_element?(lv, "#chore-event-#{event_id}", "Oct 6")
    assert has_element?(lv, "#chore-event-#{event_id}", "1h 30m")
    refute has_element?(lv, "#send-changes-#{event_id}")
    assert has_element?(lv, "#no-ready-chores")
  end

  test "a chore on an activity D4H has approved cannot change here", ctx do
    %{conn: conn, team: team, member: member, category: category} = ctx

    event =
      Repo.insert!(%ChoreEvent{team_id: team.id, chore_category_id: category.id, year: 2026})

    chore = chore_fixture(member, category, %{status: :accepted, chore_event_id: event.id})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")
    assert has_element?(lv, "#chore-change")

    event |> Ecto.Changeset.change(locked: true) |> Repo.update!()

    {:ok, _lv, html} =
      lv
      |> form("#decline-form", decline: %{reason: "Wrong"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "This chore cannot change. D4H has approved its activity."
    assert Repo.get!(Chore, chore.id).status == :accepted

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/chores/#{chore.id}")
    assert has_element?(lv, "#chore-locked")
    refute has_element?(lv, "#chore-change")
    refute has_element?(lv, "#decline-form")

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/chores/#{chore.id}/edit")
    end
  end
end
