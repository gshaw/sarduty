defmodule Web.ProposedChangeLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.Model.Chore
  alias App.Operation.ProposeAttendanceChanges
  alias App.Operation.ProposeChores

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    activity = activity_fixture(team, %{title: "Rope rescue"})
    mei = member_fixture(team, %{name: "Mei Chen"})

    {:ok, change_set, []} =
      ProposeAttendanceChanges.call(
        team,
        user,
        activity.id,
        [%{"member_id" => mei.id, "status" => "attended", "reason" => "Sheet row 3"}],
        "Sign-in sheet for Rope rescue",
        DateTime.utc_now()
      )

    %{
      conn: log_in_user(conn, user),
      team: team,
      user: user,
      activity: activity,
      change_set: change_set
    }
  end

  test "lists sets waiting for review", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/proposed-changes")
    assert has_element?(lv, "#proposed-view-waiting[aria-current]", "1")
    assert has_element?(lv, "#proposed-#{ctx.change_set.id}", "Sign-in sheet for Rope rescue")
  end

  test "a discarded set leaves Waiting for review and shows under Discarded", ctx do
    ChangeSet.discard!(ctx.change_set, DateTime.utc_now())

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/proposed-changes")
    refute has_element?(lv, "#proposed-#{ctx.change_set.id}")
    assert has_element?(lv, "#none-in-view")

    lv |> element("#proposed-view-discarded") |> render_click()
    assert has_element?(lv, "#proposed-#{ctx.change_set.id}", "Discarded")

    lv |> element("#proposed-view-all") |> render_click()
    assert has_element?(lv, "#proposed-#{ctx.change_set.id}", "Discarded")
  end

  test "shows each change with its reason, ticked", ctx do
    {:ok, lv, _html} =
      live(ctx.conn, ~p"/teams/#{ctx.team}/proposed-changes/#{ctx.change_set.id}")

    [row] = ctx.change_set.rows

    assert has_element?(lv, "#row-#{row.id}", "Mei Chen")
    assert has_element?(lv, "#row-#{row.id}", "Add as attended")
    assert has_element?(lv, "#row-#{row.id}", "Sheet row 3")
    assert has_element?(lv, "#select-#{row.id}[checked]")
  end

  test "discarding sends nothing", ctx do
    {:ok, lv, _html} =
      live(ctx.conn, ~p"/teams/#{ctx.team}/proposed-changes/#{ctx.change_set.id}")

    lv |> element("#discard") |> render_click()

    assert ChangeSet.count_waiting(ctx.team.id) == 0
  end

  test "a remove and a change of status read in the glossary's words", ctx do
    sam = member_fixture(ctx.team, %{name: "Sam Ortiz"})
    pat = member_fixture(ctx.team, %{name: "Pat Lee"})
    row = attendance_fixture(ctx.activity, sam, %{status: "absent"})
    attendance_fixture(ctx.activity, pat, %{status: "absent"})

    {:ok, change_set, []} =
      ProposeAttendanceChanges.call(
        ctx.team,
        ctx.user,
        ctx.activity.id,
        [
          %{"attendance_id" => row.id, "status" => "remove"},
          %{"member_id" => pat.id, "status" => "attended"}
        ],
        "Fixes",
        DateTime.utc_now()
      )

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/proposed-changes/#{change_set.id}")
    [remove, change] = change_set.rows

    assert has_element?(lv, "#row-#{remove.id}", "Remove: absent")
    assert has_element?(lv, "#row-#{change.id}", "Absent to attended")
  end

  test "proposed chores are accepted, and one matching a logged chore starts cleared", ctx do
    team =
      ctx.team
      |> Ecto.Changeset.change(member_logins: true, chores_enabled: true)
      |> App.Repo.update!()

    category = chore_category_fixture(team, %{title: "Office admin"})
    mei = member_fixture(team, %{name: "Ana Diaz"})
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    App.Repo.insert!(%Chore{
      team_id: team.id,
      member_id: mei.id,
      chore_category_id: category.id,
      date: today,
      minutes: 60,
      description: "Radios",
      status: :accepted
    })

    chore = %{
      "member_id" => mei.id,
      "chore_category_id" => category.id,
      "date" => Date.to_iso8601(today),
      "minutes" => 60,
      "description" => "Radios"
    }

    {:ok, change_set, [], [_check]} =
      ProposeChores.call(team, ctx.user, [chore], "Work party", DateTime.utc_now())

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{team}/proposed-changes/#{change_set.id}")
    [row] = change_set.rows

    assert has_element?(lv, "#row-#{row.id}", "already has 1 hour of Office admin")
    refute has_element?(lv, "#select-#{row.id}[checked]")
    assert has_element?(lv, "#send", "Add 0 chores")
  end
end
