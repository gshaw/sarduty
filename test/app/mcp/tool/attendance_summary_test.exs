defmodule App.MCP.Tool.AttendanceSummaryTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.AttendanceSummary

  @start ~N[2026-01-01 08:00:00]
  @finish ~N[2026-04-01 07:00:00]

  defp member(id, name, attrs \\ %{}),
    do: Map.merge(%{id: id, name: name, joined_at: ~U[2020-01-01 00:00:00Z], left_at: nil}, attrs)

  defp row(member_id, activity_id, attrs) do
    Map.merge(
      %{
        member_id: member_id,
        activity_id: activity_id,
        started_at: ~U[2026-02-01 17:00:00Z],
        finished_at: ~U[2026-02-01 19:00:00Z],
        duration_in_minutes: 999,
        tags: ["Primary Hours"],
        activity_kind: "exercise"
      },
      attrs
    )
  end

  test "sums hours per tag and kind, and counts each activity once" do
    rows = [
      row(1, 10, %{}),
      row(1, 11, %{tags: ["Primary Hours", "Rope"], finished_at: ~U[2026-02-01 18:30:00Z]}),
      row(1, 12, %{tags: ["Primary Hours"], activity_kind: "incident"})
    ]

    [pat] = AttendanceSummary.summarize([member(1, "Pat")], rows, @start, @finish)

    assert pat["total_hours"] == 5.5
    assert pat["activities"] == 3

    assert pat["by_tag"] == [
             %{
               "tag" => "Primary Hours",
               "activity_kind" => "exercise",
               "hours" => 3.5,
               "activities" => 2
             },
             %{
               "tag" => "Primary Hours",
               "activity_kind" => "incident",
               "hours" => 2.0,
               "activities" => 1
             },
             %{"tag" => "Rope", "activity_kind" => "exercise", "hours" => 1.5, "activities" => 1}
           ]
  end

  test "an untagged activity counts under a null tag, last" do
    rows = [row(1, 10, %{tags: []}), row(1, 11, %{tags: nil}), row(1, 12, %{})]
    [pat] = AttendanceSummary.summarize([member(1, "Pat")], rows, @start, @finish)

    assert Enum.map(pat["by_tag"], &{&1["tag"], &1["activities"]}) == [
             {"Primary Hours", 1},
             {nil, 2}
           ]
  end

  test "uses D4H's duration when a time is missing, and never counts below zero" do
    rows = [
      row(1, 10, %{finished_at: nil, duration_in_minutes: 45}),
      row(1, 11, %{started_at: nil, duration_in_minutes: nil}),
      row(1, 12, %{finished_at: ~U[2026-02-01 16:00:00Z]})
    ]

    [pat] = AttendanceSummary.summarize([member(1, "Pat")], rows, @start, @finish)
    assert pat["total_hours"] == 0.75
  end

  test "lists members on the team during the range with 0 hours, and leaves out the rest" do
    members = [
      member(1, "Current"),
      member(2, "Left before", %{left_at: ~U[2025-12-01 00:00:00Z]}),
      member(3, "Joined after", %{joined_at: ~U[2026-05-01 00:00:00Z]}),
      member(4, "Left during", %{left_at: ~U[2026-02-15 00:00:00Z]}),
      member(5, "Left before, but attended", %{left_at: ~U[2025-12-01 00:00:00Z]})
    ]

    summary = AttendanceSummary.summarize(members, [row(5, 10, %{})], @start, @finish)

    assert Enum.map(summary, & &1["name"]) == [
             "Current",
             "Left before, but attended",
             "Left during"
           ]

    current = hd(summary)
    assert current["total_hours"] == 0.0
    assert current["by_tag"] == []
  end
end
