defmodule App.MCP.Tool.ListActivitiesTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.ListActivities

  defp activity(id, started_at, tags) do
    %{
      id: id,
      title: "Activity #{id}",
      activity_kind: "exercise",
      tags: tags,
      started_at: started_at,
      finished_at: DateTime.add(started_at, 3600),
      is_published: true,
      chore_minutes: nil,
      attended: 3,
      signed_up: 0,
      address: "1 Secret Road"
    }
  end

  defp activities do
    [
      activity(1, ~U[2026-03-02 17:00:00Z], ["Rope"]),
      activity(2, ~U[2026-03-01 17:00:00Z], ["Primary Hours", "rope"]),
      activity(3, ~U[2026-03-03 17:00:00Z], nil)
    ]
  end

  @hours_tags %{primary: "Primary Hours", secondary: "Secondary Hours", other: "No Hours"}

  defp build(activities, filters, timezone \\ "Etc/UTC"),
    do:
      ListActivities.build(
        activities,
        Map.merge(%{tag: nil, hours: nil}, filters),
        @hours_tags,
        timezone
      )

  test "lists oldest first, with no address" do
    output = build(activities(), %{}, "America/Vancouver")

    assert Enum.map(output, & &1["id"]) == [2, 1, 3]
    assert Enum.at(output, 2)["tags"] == []
    [first | _rest] = output
    assert first["started_at"] == "2026-03-01T09:00:00-08:00"
    refute Map.has_key?(first, "address")
  end

  test "a tag matches without regard to case" do
    rope = build(activities(), %{tag: "ROPE"})
    assert Enum.map(rope, & &1["id"]) == [2, 1]
    assert build(activities(), %{tag: "Training"}) == []
  end

  test "gives hours, length, published, and counts, and filters by hours" do
    [primary | _rest] = output = build(activities(), %{})

    assert primary["hours"] == "primary"
    assert primary["minutes"] == 60
    assert primary["published"]
    assert primary["attended"] == 3
    untagged = build(activities(), %{hours: "none"})
    assert Enum.map(untagged, & &1["id"]) == [1, 3]
    assert Enum.map(output, & &1["kind"]) == ~w(exercise exercise exercise)
  end

  test "a chore activity is kind chores" do
    chores = %{activity(4, ~U[2026-03-01 08:00:00Z], ["Primary Hours"]) | chore_minutes: 90}
    assert [%{"kind" => "chores"}] = build([chores], %{})
  end
end
