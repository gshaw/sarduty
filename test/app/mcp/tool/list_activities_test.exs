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

  test "lists oldest first, with no address" do
    output = ListActivities.build(activities(), nil, "America/Vancouver")

    assert Enum.map(output, & &1["id"]) == [2, 1, 3]
    assert Enum.at(output, 2)["tags"] == []
    [first | _rest] = output
    assert first["started_at"] == "2026-03-01T09:00:00-08:00"
    refute Map.has_key?(first, "address")
  end

  test "a tag matches without regard to case" do
    rope = ListActivities.build(activities(), "ROPE", "Etc/UTC")
    assert Enum.map(rope, & &1["id"]) == [2, 1]
    assert ListActivities.build(activities(), "Training", "Etc/UTC") == []
  end
end
