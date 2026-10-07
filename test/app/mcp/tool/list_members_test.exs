defmodule App.MCP.Tool.ListMembersTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.ListMembers

  test "gives each member their groups by name, and times in the team's zone" do
    members = [
      %{
        id: 2,
        name: "Sam",
        position: "MIT",
        joined_at: ~U[2024-03-01 08:00:00Z],
        left_at: nil,
        d4h_status: "OPERATIONAL",
        email: "sam@example.com"
      },
      %{
        id: 1,
        name: "Alex",
        position: nil,
        joined_at: ~U[2020-01-01 08:00:00Z],
        left_at: ~U[2025-06-30 07:00:00Z],
        d4h_status: "RETIRED",
        email: "alex@example.com"
      }
    ]

    [alex, sam] =
      ListMembers.build(members, [{2, "Rope"}, {2, "Provisional"}], "America/Vancouver")

    assert alex["groups"] == []
    assert alex["left_at"] == "2025-06-30T00:00:00-07:00"
    assert sam["groups"] == ["Provisional", "Rope"]
    assert sam["joined_at"] == "2024-03-01T00:00:00-08:00"
    assert sam["left_at"] == nil
    refute Map.has_key?(sam, "email")
  end
end
