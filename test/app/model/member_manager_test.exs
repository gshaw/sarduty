defmodule App.Model.MemberManagerTest do
  use ExUnit.Case, async: true

  alias App.Model.Member

  @now ~U[2026-10-04 12:00:00Z]

  defp manager?(attrs) do
    %Member{d4h_permission: 0, d4h_status: "OPERATIONAL", left_at: nil}
    |> struct(attrs)
    |> Member.manager?(@now)
  end

  test "owners and editors are managers, whatever their operational status" do
    assert manager?(d4h_permission: 0)
    assert manager?(d4h_permission: 1, d4h_status: "NON_OPERATIONAL")
  end

  test "other access levels, and members not yet synced, are not" do
    for permission <- [2, 3, 4, nil] do
      refute manager?(d4h_permission: permission)
    end
  end

  test "retired members and members who left are not" do
    refute manager?(d4h_status: "RETIRED")
    refute manager?(left_at: ~U[2026-09-01 00:00:00Z])
    assert manager?(left_at: ~U[2026-11-01 00:00:00Z])
  end
end
