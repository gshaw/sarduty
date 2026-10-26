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
      ListMembers.build(
        members,
        [{2, "Rope"}, {2, "Provisional"}],
        %{1 => :retired, 2 => {:away, %{reason: "Parental leave", ends_on: ~D[2027-03-01]}}},
        "America/Vancouver"
      )

    assert alex["groups"] == []
    assert alex["left_at"] == "2025-06-30T00:00:00-07:00"
    assert sam["groups"] == ["Provisional", "Rope"]
    assert sam["joined_at"] == "2024-03-01T00:00:00-08:00"
    assert sam["left_at"] == nil
    refute Map.has_key?(sam, "email")
    assert alex["standing"] == "retired"
  end

  test "an away member is away, with no reason or dates" do
    member = %{id: 1, name: "Sam", position: nil, joined_at: nil, left_at: nil, d4h_status: nil}
    period = %{reason: "Parental leave", ends_on: ~D[2027-03-01]}

    [sam] = ListMembers.build([member], [], %{1 => {:away, period}}, "Etc/UTC")

    assert sam["standing"] == "away"
    refute inspect(sam) =~ "Parental"
    refute inspect(sam) =~ "2027"
  end
end
