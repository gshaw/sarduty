defmodule App.Operation.RefreshD4HData.PlanDeletedActivitiesTest do
  use ExUnit.Case, async: true

  alias App.Operation.RefreshD4HData.UpsertActivities

  @deleted_at ~U[2026-10-05 06:00:00Z]

  defp activity(id, d4h_id, deleted_at \\ nil),
    do: %{id: id, d4h_activity_id: d4h_id, deleted_at: deleted_at}

  test "marks the activities D4H no longer lists" do
    activities = [activity(1, 101), activity(2, 102), activity(3, 103)]

    assert UpsertActivities.plan_deleted(activities, MapSet.new([101, 103])) ==
             %{delete: [2], restore: []}
  end

  test "leaves activities already marked alone" do
    activities = [activity(1, 101), activity(2, 102, @deleted_at)]

    assert UpsertActivities.plan_deleted(activities, MapSet.new([101])) ==
             %{delete: [], restore: []}
  end

  test "brings back an activity D4H lists again" do
    activities = [activity(1, 101), activity(2, 102, @deleted_at)]

    assert UpsertActivities.plan_deleted(activities, MapSet.new([101, 102])) ==
             %{delete: [], restore: [2]}
  end

  test "changes nothing when D4H lists none of the kind" do
    activities = [activity(1, 101), activity(2, 102, @deleted_at)]

    assert UpsertActivities.plan_deleted(activities, MapSet.new()) ==
             %{delete: [], restore: []}
  end

  test "a D4H activity with no local row is not in the plan" do
    assert UpsertActivities.plan_deleted([activity(1, 101)], MapSet.new([101, 999])) ==
             %{delete: [], restore: []}
  end
end
