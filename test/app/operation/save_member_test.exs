defmodule App.Operation.SaveMemberTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Operation.SaveMember
  alias App.ViewModel.MemberFormViewModel

  @tz "America/Halifax"

  defp member do
    %Member{
      id: 7,
      d4h_member_id: 70,
      name: "Pat Example",
      email: "pat@example.com",
      phone: "902-555-0100",
      ref_id: "",
      d4h_status: "OPERATIONAL",
      d4h_permission: 1,
      joined_at: ~U[2025-03-01 04:00:00Z]
    }
  end

  defp values(overrides \\ %{}) do
    struct(
      MemberFormViewModel.from_member(member(), @tz, nil),
      overrides
    )
  end

  test "a new member is a create with every field, joining at midnight in the team's zone" do
    row = SaveMember.plan(nil, values(%{name: "New Person"}), @tz)

    assert row.action == :create_member
    assert row.new_value["name"] == "New Person"
    assert row.new_value["joined_at"] == "2025-03-01T04:00:00Z"
    assert row.new_value["permission"] == 0
  end

  test "an unchanged form changes nothing, an Editor reading as a team admin" do
    assert SaveMember.plan(member(), values(), @tz) == :unchanged
  end

  test "an update names only what changed, with the old value" do
    row = SaveMember.plan(member(), values(%{phone: "902-555-0199", team_admin: false}), @tz)

    assert row.action == :update_member
    assert row.d4h_record_id == 70
    assert row.new_value == %{"phone" => "902-555-0199", "permission" => 2}
    assert row.old_value == %{"phone" => "902-555-0100", "permission" => 0}
  end

  test "saving a retired member's details leaves them retired" do
    retired = %{member() | d4h_status: "RETIRED"}
    form = MemberFormViewModel.from_member(retired, @tz, nil)
    assert SaveMember.plan(retired, form, @tz) == :unchanged
  end
end
