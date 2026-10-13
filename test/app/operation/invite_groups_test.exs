defmodule App.Operation.InviteGroupsTest do
  use ExUnit.Case, async: true

  alias App.Model.Activity
  alias App.Model.Group
  alias App.Model.Member
  alias App.Operation.InviteGroups

  @starts ~U[2026-10-20 18:00:00Z]
  @ends ~U[2026-10-20 21:00:00Z]

  defp activity, do: %Activity{d4h_activity_id: 900, started_at: @starts, finished_at: @ends}
  defp member(id), do: %Member{id: id, d4h_member_id: 100 + id}

  test "each member is invited as requested, for the activity's times" do
    managers = %Group{title: "Search Managers"}

    assert [row] = InviteGroups.plan(activity(), [{managers, [member(1)]}], [])
    assert row.action == :create_attendance
    assert row.member_id == 1
    assert row.reason == "In the Search Managers group"

    assert row.new_value == %{
             "d4h_activity_id" => 900,
             "d4h_member_id" => 101,
             "status" => "REQUESTED",
             "starts_at" => "2026-10-20T18:00:00Z",
             "ends_at" => "2026-10-20T21:00:00Z"
           }
  end

  test "a member in two groups is invited once, from the first" do
    managers = %Group{title: "Search Managers"}
    rope = %Group{title: "Rope"}

    rows =
      InviteGroups.plan(activity(), [{managers, [member(1)]}, {rope, [member(1), member(2)]}], [])

    assert Enum.map(rows, &{&1.member_id, &1.reason}) == [
             {1, "In the Search Managers group"},
             {2, "In the Rope group"}
           ]
  end

  # D4H would add a second row for them.
  test "a member on the activity already is left out" do
    managers = %Group{title: "Search Managers"}
    rows = InviteGroups.plan(activity(), [{managers, [member(1), member(2)]}], [1])
    assert Enum.map(rows, & &1.member_id) == [2]
  end
end
