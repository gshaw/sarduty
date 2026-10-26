defmodule App.Operation.SaveActivityTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H
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

  test "a new activity sends its pin, and none when it has none (#610)" do
    form = %ActivityFormViewModel{
      title: "Night navigation",
      starts_at: ~N[2026-10-08 18:30:00],
      ends_at: ~N[2026-10-08 23:00:00],
      coordinate: "45.36531,-63.27972"
    }

    assert SaveActivity.plan(nil, form, @tag_ids, @team).new_value["location"] ==
             "45.36531,-63.27972"

    refute Map.has_key?(
             SaveActivity.plan(nil, %{form | coordinate: nil}, @tag_ids, @team).new_value,
             "location"
           )
  end

  test "a moved or removed pin is a change of location (#610)" do
    activity = %{activity() | coordinate: "49.1,-123.1"}
    values = struct(ActivityFormViewModel.from_activity(activity, @team), %{})

    assert SaveActivity.plan(activity, values, @tag_ids, @team) == :unchanged

    moved = SaveActivity.plan(activity, %{values | coordinate: "49.2,-123.1"}, @tag_ids, @team)
    assert moved.new_value == %{"location" => "49.2,-123.1"}
    assert moved.old_value["location"] == "49.10000,-123.10000"

    removed = SaveActivity.plan(activity, %{values | coordinate: nil}, @tag_ids, @team)
    assert removed.new_value == %{"location" => nil}
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

  describe "on a D4H team (#585)" do
    test "a new activity adds no one's attendance and sends its description as HTML" do
      form = %ActivityFormViewModel{
        title: "Practice",
        description: "Bring a headlamp.\nAnd a map.",
        starts_at: ~N[2026-10-08 18:00:00],
        ends_at: ~N[2026-10-08 20:00:00]
      }

      row = SaveActivity.plan(nil, form, @tag_ids, @team)

      assert row.new_value["full_team"] == false
      assert row.new_value["shared"] == false
      assert row.new_value["description"] == "<p>Bring a headlamp.<br>And a map.</p>"
    end

    test "an untouched description is not sent, and a changed one goes as HTML" do
      activity = %{activity() | description: "<p>Bring a headlamp.</p>"}
      form = ActivityFormViewModel.from_activity(activity, @team)
      assert form.description == "Bring a headlamp."
      assert SaveActivity.plan(activity, form, @tag_ids, @team) == :unchanged

      row =
        SaveActivity.plan(activity, %{form | description: "Bring 2 headlamps."}, @tag_ids, @team)

      assert row.new_value == %{"description" => "<p>Bring 2 headlamps.</p>"}
      assert row.old_value["description"] == "<p>Bring a headlamp.</p>"
    end

    test "a description with formatting is left out" do
      activity = %{activity() | description: ~s(<ul><li>Headlamp</li></ul>)}
      assert ActivityFormViewModel.description_locked?(activity, @team)
      form = ActivityFormViewModel.from_activity(activity, @team)

      row =
        SaveActivity.plan(
          activity,
          %{form | description: "Headlamp", title: "Nav"},
          @tag_ids,
          @team
        )

      assert row.new_value == %{"title" => "Nav"}
    end

    test "a published activity changes only its published flag" do
      activity = %{activity() | is_published: true}
      form = ActivityFormViewModel.from_activity(activity, @team)
      changed = %{form | hours: "secondary", title: "Nav"}
      assert SaveActivity.plan(activity, changed, @tag_ids, @team) == :unchanged

      row = SaveActivity.plan(activity, %{changed | published: false}, @tag_ids, @team)
      assert row.new_value == %{"published" => false}
    end

    test "a Records team's description is its text" do
      team = %Team{timezone: @tz, d4h_api_host: D4H.records_host()}
      activity = %{activity() | description: "<ul><li>Headlamp</li></ul>"}
      refute ActivityFormViewModel.description_locked?(activity, team)
      form = ActivityFormViewModel.from_activity(activity, team)

      row =
        SaveActivity.plan(
          activity,
          %{form | description: "Headlamp", hours: "none"},
          @tag_ids,
          team
        )

      assert row.new_value == %{"description" => "Headlamp", "tag_ids" => [3]}
    end
  end
end
