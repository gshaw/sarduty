defmodule App.Operation.SaveActivityTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.SaveActivity
  alias App.ViewModel.ActivityFormViewModel

  @tz "America/Halifax"
  @team %Team{timezone: @tz}
  @tag_ids %{"Primary Hours" => 1, "Secondary Hours" => 2, "Training" => 3}

  defp activity do
    %Activity{
      id: 5,
      d4h_activity_id: 50,
      activity_kind: "exercise",
      title: "Night navigation",
      address: "Victoria Park",
      started_at: ~U[2026-10-01 21:00:00Z],
      finished_at: ~U[2026-10-02 00:00:00Z],
      tags: ["Primary Hours", "Training"],
      is_published: false
    }
  end

  defp values(overrides),
    do: struct(ActivityFormViewModel.from_activity(activity(), @team), overrides)

  test "a new activity is a create with its kind, times in UTC, and its hours tag" do
    form = %ActivityFormViewModel{
      kind: "incident",
      title: "Missing hiker",
      starts_at: ~N[2026-10-08 18:30:00],
      ends_at: ~N[2026-10-08 23:00:00],
      hours: "primary"
    }

    row = SaveActivity.plan(nil, form, @tag_ids, @team)

    assert row.action == :create_activity
    assert row.new_value["kind"] == "incident"
    assert row.new_value["started_at"] == "2026-10-08T21:30:00Z"
    assert row.new_value["tag_ids"] == [1]
  end

  test "an unchanged form changes nothing" do
    assert SaveActivity.plan(activity(), values(%{}), @tag_ids, @team) == :unchanged
  end

  test "changing the hours swaps the hours tag and keeps the others" do
    row = SaveActivity.plan(activity(), values(%{hours: "secondary"}), @tag_ids, @team)

    assert row.action == :update_activity
    assert row.new_value == %{"tag_ids" => [2, 3]}
    assert row.old_value["kind"] == "exercise"
  end

  test "a change names only the fields that differ" do
    row = SaveActivity.plan(activity(), values(%{title: "Night nav"}), @tag_ids, @team)
    assert row.new_value == %{"title" => "Night nav"}
    assert row.old_value == %{"title" => "Night navigation", "kind" => "exercise"}
  end

  test "a team in an organization gets the organization's hours tags" do
    team = %Team{
      timezone: @tz,
      organization: %Organization{
        primary_hours_tag: "SRVTC Primary Activity",
        secondary_hours_tag: "SRVTC Secondary Activity"
      }
    }

    tag_ids = %{"SRVTC Primary Activity" => 7, "SRVTC Secondary Activity" => 8, "Training" => 3}
    activity = %{activity() | tags: ["SRVTC Primary Activity", "Training"]}

    assert ActivityFormViewModel.from_activity(activity, team).hours == "primary"

    values = struct(ActivityFormViewModel.from_activity(activity, team), hours: "secondary")
    row = SaveActivity.plan(activity, values, tag_ids, team)
    assert row.new_value == %{"tag_ids" => [3, 8]}
  end

  # The form's time inputs send minutes, so seconds from D4H must not read as a change.
  test "seconds in a stored time do not count as a change" do
    activity = %{activity() | started_at: ~U[2026-10-01 21:00:42Z]}
    form = ActivityFormViewModel.from_activity(activity, @team)
    assert SaveActivity.plan(activity, form, @tag_ids, @team) == :unchanged
  end
end
