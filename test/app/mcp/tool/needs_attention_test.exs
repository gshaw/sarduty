defmodule App.MCP.Tool.NeedsAttentionTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.NeedsAttention

  test "gives each item's key, level, title, and detail, with its year or activity" do
    items = [
      %{
        key: :untagged,
        level: :info,
        year: 2026,
        title: "3 activities in 2026 have no hours tag",
        detail: "Add one",
        action: "Show activities"
      },
      %{
        key: :attendance_to_send,
        level: :info,
        activity_id: 7,
        title: "Attendance to send",
        detail: nil,
        action: "Send attendance"
      }
    ]

    [untagged, attendance] = NeedsAttention.build(items)

    assert untagged["key"] == "untagged"
    assert untagged["year"] == 2026
    assert attendance["activity_id"] == 7
    refute Map.has_key?(attendance, "action")
  end
end
