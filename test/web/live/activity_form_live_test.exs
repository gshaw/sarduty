defmodule Web.ActivityFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Operation.ApplyChangeSet
  alias App.Operation.SaveActivity
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = hosted_team_with_user_fixture()
    %{conn: log_in_user(conn, user), team: team, user: user}
  end

  defp add_activity(conn, team, fields) do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

    lv
    |> form("#activity-form", form: fields)
    |> render_submit()
    |> follow_redirect(conn)
  end

  test "a team admin adds an activity that counts for primary hours", %{conn: conn, team: team} do
    {:ok, list, _html} = live(conn, ~p"/teams/#{team}/activities")
    assert has_element?(list, "#activity-add")

    {:ok, page, html} =
      add_activity(conn, team, %{
        kind: "incident",
        title: "Missing hiker",
        starts_at: "2026-10-08T18:30",
        ends_at: "2026-10-08T23:00",
        place: "Victoria Park",
        hours: "primary"
      })

    assert html =~ "Saved Missing hiker."
    assert has_element?(page, "#activity-edit")
    activity = Repo.get_by!(Activity, team_id: team.id, title: "Missing hiker")
    assert activity.activity_kind == "incident"
    assert activity.tags == [Activity.primary_hours_tag()]
    assert activity.started_at == ~U[2026-10-08 21:30:00Z]
    assert activity.address == "Victoria Park"
    assert activity.ref_id == "00001"
  end

  test "attendance sent to a hosted activity reaches the copy", %{team: team, user: user} do
    {:ok, activity} =
      SaveActivity.call(
        team,
        nil,
        %{
          "title" => "Mock search",
          "starts_at" => "2026-10-08T18:00",
          "ends_at" => "2026-10-08T21:00"
        },
        user,
        DateTime.utc_now()
      )

    member = Repo.get_by!(Member, team_id: team.id)

    change_set =
      ChangeSet.propose!(%ChangeSet{team_id: team.id, activity_id: activity.id, source: :door}, [
        %ChangeSetRow{
          action: :create_attendance,
          member_id: member.id,
          new_value: %{
            "d4h_activity_id" => activity.d4h_activity_id,
            "d4h_member_id" => member.d4h_member_id,
            "status" => "ATTENDING",
            "starts_at" => "2026-10-08T21:00:00Z",
            "ends_at" => "2026-10-09T00:00:00Z"
          }
        }
      ])

    assert {:ok, [%{status: :applied}]} =
             ApplyChangeSet.call(team, change_set, user, DateTime.utc_now())
  end

  test "a team admin changes an activity and deletes it", %{conn: conn, team: team} do
    {:ok, _page, _html} =
      add_activity(conn, team, %{
        title: "Practice",
        starts_at: "2026-10-08T18:00",
        ends_at: "2026-10-08T20:00"
      })

    activity = Repo.get_by!(Activity, team_id: team.id, title: "Practice")
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")

    lv
    |> form("#activity-form", form: %{hours: "secondary", title: "Rope practice"})
    |> render_submit()

    activity = Repo.reload!(activity)
    assert activity.title == "Rope practice"
    assert activity.tags == [Activity.secondary_hours_tag()]

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/edit")
    lv |> element("#activity-delete-button") |> render_click()
    assert Repo.reload!(activity).deleted_at
  end

  test "an end before the start is refused", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/new")

    html =
      lv
      |> form("#activity-form",
        form: %{title: "Backwards", starts_at: "2026-10-08T18:00", ends_at: "2026-10-08T17:00"}
      )
      |> render_submit()

    assert html =~ "Enter an end after the start."
  end
end
