defmodule App.Operation.BuildYetToArriveTest do
  use ExUnit.Case, async: true

  alias App.Operation.BuildYetToArrive

  defp member(id, name), do: %{id: id, name: name}

  defp scan(member_id, kind \\ "arrived", name \\ "Member"),
    do: %{member_id: member_id, kind: kind, member: member(member_id, name)}

  test "lists members who signed up and have no scan, by name" do
    signed_up = [member(1, "Zoe"), member(2, "amir"), member(3, "Bea")]

    result = BuildYetToArrive.call(signed_up, [scan(3)])

    assert Enum.map(result.yet_to_arrive, & &1.name) == ["amir", "Zoe"]
    assert result.signed_up == 3
  end

  test "a member scanned leaving has come, so drops off" do
    result = BuildYetToArrive.call([member(1, "Zoe")], [scan(1, "left")])
    assert result.yet_to_arrive == []
  end

  test "counts arrivals once each, and walk-ins who did not sign up" do
    result = BuildYetToArrive.call([member(1, "Zoe")], [scan(1), scan(1, "left"), scan(9)])
    assert %{arrived: 2, walk_ins: 1} = result
  end

  test "here is everyone whose latest scan is an arrival, walk-ins too, by name" do
    scans = [
      scan(1, "arrived", "Zoe"),
      scan(2, "arrived", "amir"),
      scan(2, "left", "amir"),
      scan(3, "arrived", "Bea"),
      scan(3, "left", "Bea"),
      scan(3, "arrived", "Bea")
    ]

    result = BuildYetToArrive.call([member(1, "Zoe")], scans)

    assert Enum.map(result.here, & &1.member.name) == ["Bea", "Zoe"]
    assert Enum.all?(result.here, &(&1.kind == "arrived"))
  end
end
