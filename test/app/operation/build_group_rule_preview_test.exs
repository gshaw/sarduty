defmodule App.Operation.BuildGroupRulePreviewTest do
  use ExUnit.Case, async: true

  alias App.Operation.BuildGroupRulePreview

  @now ~U[2026-09-10 12:00:00Z]
  @rope 1
  @swiftwater 2
  @first_aid 3

  defp award(member_id, qualification_id, attrs \\ []) do
    Map.merge(
      %{
        member_id: member_id,
        member_left_at: nil,
        d4h_qualification_id: qualification_id,
        starts_at: ~U[2025-01-01 00:00:00Z],
        ends_at: nil
      },
      Map.new(attrs)
    )
  end

  defp plan(clauses, awards, current_member_ids) do
    BuildGroupRulePreview.plan(clauses, awards, current_member_ids, @now)
  end

  test "a member must satisfy every clause" do
    awards = [award(10, @rope), award(10, @first_aid), award(11, @rope)]

    result = plan([[@rope], [@first_aid]], awards, [])

    assert result.add == MapSet.new([10])
  end

  test "any qualification in a clause satisfies it" do
    awards = [award(10, @rope), award(11, @swiftwater)]

    result = plan([[@rope, @swiftwater]], awards, [])

    assert result.add == MapSet.new([10, 11])
  end

  test "an expired award does not count" do
    awards = [
      award(10, @rope, ends_at: ~U[2026-09-01 00:00:00Z]),
      award(11, @rope, ends_at: ~U[2027-01-01 00:00:00Z])
    ]

    result = plan([[@rope]], awards, [10, 11])

    assert result.add == MapSet.new()
    assert result.remove == MapSet.new([10])
  end

  test "an award that has not started yet does not count" do
    result = plan([[@rope]], [award(10, @rope, starts_at: ~U[2026-10-01 00:00:00Z])], [10])

    assert result.remove == MapSet.new([10])
  end

  test "an expired award still counts when another award for it is active" do
    awards = [award(10, @rope, ends_at: ~U[2026-09-01 00:00:00Z]), award(10, @rope)]

    result = plan([[@rope]], awards, [10])

    assert result.remove == MapSet.new()
  end

  test "a member who has left is removed and never added" do
    left = [member_left_at: ~U[2026-08-01 00:00:00Z]]
    awards = [award(10, @rope, left), award(11, @rope, left)]

    result = plan([[@rope]], awards, [10])

    assert result.add == MapSet.new()
    assert result.remove == MapSet.new([10])
  end

  test "members who hold nothing are removed" do
    result = plan([[@rope]], [award(10, @rope)], [10, 12])

    assert result.remove == MapSet.new([12])
  end

  test "an empty clause plans no changes instead of removing everyone" do
    result = plan([[@rope], []], [award(10, @rope)], [11, 12])

    assert result.add == MapSet.new()
    assert result.remove == MapSet.new()
  end

  test "no clauses plans no changes" do
    result = plan([], [award(10, @rope)], [11])

    assert result.add == MapSet.new()
    assert result.remove == MapSet.new()
  end

  test "a qualification with no local row is reported once" do
    missing = BuildGroupRulePreview.missing_qualification_ids([[@rope, 99], [99]], [@rope])

    assert missing == [99]
  end
end
