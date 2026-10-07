defmodule App.MCP.Tool.ListQualificationsTest do
  use ExUnit.Case, async: true

  alias App.MCP.Tool.ListQualifications

  @now ~U[2026-06-01 12:00:00Z]

  defp award(member_id, name, starts_at, ends_at) do
    %{
      qualification_id: 1,
      member_id: member_id,
      member_name: name,
      starts_at: starts_at,
      ends_at: ends_at
    }
  end

  test "lists awards by member with their status as of now" do
    qualifications = [%{id: 2, title: "Rope"}, %{id: 1, title: "First Aid"}]

    awards = [
      award(2, "Sam", ~U[2023-01-01 00:00:00Z], ~U[2026-01-01 00:00:00Z]),
      award(2, "Sam", ~U[2026-01-01 00:00:00Z], ~U[2029-01-01 00:00:00Z]),
      award(1, "Alex", ~U[2020-01-01 00:00:00Z], nil),
      award(3, "Kim", ~U[2026-07-01 00:00:00Z], nil)
    ]

    [first_aid, rope] = ListQualifications.build(qualifications, awards, "Etc/UTC", @now)

    assert rope["awards"] == []

    assert Enum.map(first_aid["awards"], &{&1["member_name"], &1["status"]}) == [
             {"Alex", "current"},
             {"Kim", "not_started"},
             {"Sam", "expired"},
             {"Sam", "current"}
           ]

    assert hd(first_aid["awards"])["ends_at"] == nil
  end
end
