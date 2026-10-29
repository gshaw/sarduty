defmodule App.ViewData.TeamDashboardViewDataTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Model.Activity
  alias App.Model.AttendanceScan
  alias App.ViewData.TeamDashboardViewData

  @now ~U[2026-10-06 16:00:00Z]

  defp activity(id, starts_in_hours, hours_long \\ 2) do
    started_at = DateTime.add(@now, round(starts_in_hours * 60), :minute)
    %{id: id, started_at: started_at, finished_at: DateTime.add(started_at, hours_long, :hour)}
  end

  defp ids(activities), do: Enum.map(activities, & &1.id)

  test "NextUp is an activity starting within 12 hours, and Coming up leaves it out" do
    {next_up, coming_up} =
      TeamDashboardViewData.agenda([activity(2, 30), activity(1, 3)], @now)

    assert next_up.id == 1
    assert ids(coming_up) == [2]
  end

  test "an activity still running is NextUp until it finishes" do
    {next_up, _} = TeamDashboardViewData.agenda([activity(1, -2, 4)], @now)
    assert next_up.id == 1

    {next_up, coming_up} = TeamDashboardViewData.agenda([activity(1, -3, 2)], @now)
    assert next_up == nil
    assert coming_up == []
  end

  test "nothing within 12 hours means no NextUp" do
    {next_up, coming_up} = TeamDashboardViewData.agenda([activity(1, 12.5)], @now)

    assert next_up == nil
    assert ids(coming_up) == [1]
  end

  test "Coming up is the next 5 within 14 days" do
    activities = for day <- 1..15, do: activity(day, day * 24)

    {nil, coming_up} = TeamDashboardViewData.agenda(activities, @now)

    assert ids(coming_up) == [1, 2, 3, 4, 5]

    {nil, coming_up} = TeamDashboardViewData.agenda([activity(15, 15 * 24)], @now)
    assert coming_up == []
  end

  describe "attendance_to_send/2 (#475)" do
    defp scan!(activity, member, at) do
      inserted_at = %{at | microsecond: {0, 6}}

      AttendanceScan.insert!(%AttendanceScan{
        team_id: activity.team_id,
        activity_id: activity.id,
        member_id: member.id,
        kind: "arrived",
        method: "name",
        scanned_at: inserted_at,
        inserted_at: inserted_at,
        updated_at: inserted_at
      })
    end

    defp finished(team, days_ago) do
      finished_at = DateTime.add(@now, -days_ago, :day)

      activity_fixture(team, %{
        started_at: DateTime.add(finished_at, -2, :hour),
        finished_at: finished_at
      })
    end

    test "lists finished activities with scans nobody sent, oldest first" do
      team = team_fixture()
      member = member_fixture(team)
      older = finished(team, 5)
      newer = finished(team, 1)
      _no_scans = finished(team, 2)
      too_old = finished(team, 31)

      running =
        activity_fixture(team, %{
          started_at: DateTime.add(@now, -1, :hour),
          finished_at: DateTime.add(@now, 1, :hour)
        })

      other_team = finished(team_fixture(), 1)

      for activity <- [older, newer, newer, too_old, running, other_team],
          do: scan!(activity, member, DateTime.add(activity.finished_at, -1, :hour))

      assert [
               %{id: older_id},
               %{id: newer_id, title: title}
             ] = TeamDashboardViewData.attendance_to_send(team, @now)

      assert {older_id, newer_id, title} == {older.id, newer.id, newer.title}
    end

    test "attendance sent clears it, and a scan after brings it back" do
      team = team_fixture()
      member = member_fixture(team)
      activity = finished(team, 1)
      scan!(activity, member, DateTime.add(@now, -26, :hour))
      Activity.mark_attendance_sent(activity, DateTime.add(@now, -25, :hour))

      assert TeamDashboardViewData.attendance_to_send(team, @now) == []

      scan!(activity, member, DateTime.add(@now, -24, :hour))
      assert [%{id: id}] = TeamDashboardViewData.attendance_to_send(team, @now)
      assert id == activity.id
    end

    test "the mark never moves back" do
      team = team_fixture()
      activity = finished(team, 1)
      scan!(activity, member_fixture(team), DateTime.add(@now, -26, :hour))
      Activity.mark_attendance_sent(activity, DateTime.add(@now, -25, :hour))
      Activity.mark_attendance_sent(activity, DateTime.add(@now, -27, :hour))

      assert TeamDashboardViewData.attendance_to_send(team, @now) == []
    end

    test "a published activity is left out: its attendance is final" do
      team = team_fixture()

      activity =
        team
        |> finished(1)
        |> Ecto.Changeset.change(is_published: true)
        |> App.Repo.update!()

      scan!(activity, member_fixture(team), DateTime.add(@now, -26, :hour))

      assert TeamDashboardViewData.attendance_to_send(team, @now) == []
    end

    test "a deleted activity is left out" do
      team = team_fixture()

      activity =
        team
        |> finished(1)
        |> Ecto.Changeset.change(deleted_at: ~U[2026-10-06 00:00:00Z])
        |> App.Repo.update!()

      scan!(activity, member_fixture(team), DateTime.add(@now, -26, :hour))

      assert TeamDashboardViewData.attendance_to_send(team, @now) == []
    end
  end

  test "counts finished drafts missing a required field, not published or coming ones (#681)" do
    team = team_fixture()
    custom_field_fixture(team, %{d4h_custom_field_id: 454, required: true})
    past = DateTime.add(@now, -2, :day)
    later = DateTime.add(@now, 2, :day)

    for {published, started_at} <- [{false, past}, {true, past}, {false, later}] do
      activity_fixture(team, %{
        activity_kind: "incident",
        is_published: published,
        started_at: started_at,
        finished_at: DateTime.add(started_at, 1, :hour),
        custom_values: %{}
      })
    end

    items = TeamDashboardViewData.attention_items(team, @now)

    assert %{title: "1 draft activity is missing required fields"} =
             Enum.find(items, &(&1.key == :missing_fields))
  end
end
