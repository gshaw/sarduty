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

  defp member(id, left_at \\ nil), do: %{id: id, left_at: left_at}

  defp plan(clauses, awards, current_members) do
    BuildGroupRulePreview.plan(clauses, awards, current_members, @now)
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

  test "an expired award does not count, and the reason says when it ended" do
    awards = [
      award(10, @rope, ends_at: ~U[2026-09-01 00:00:00Z]),
      award(11, @rope, ends_at: ~U[2027-01-01 00:00:00Z])
    ]

    result = plan([[@rope]], awards, [member(10), member(11)])

    assert result.add == MapSet.new()
    assert result.remove == %{10 => [{:expired, @rope, ~U[2026-09-01 00:00:00Z]}]}
  end

  test "the reason names the most recent of several expired awards" do
    awards = [
      award(10, @rope, ends_at: ~U[2024-09-01 00:00:00Z]),
      award(10, @rope, ends_at: ~U[2026-09-01 00:00:00Z])
    ]

    assert plan([[@rope]], awards, [member(10)]).remove == %{
             10 => [{:expired, @rope, ~U[2026-09-01 00:00:00Z]}]
           }
  end

  test "an award that has not started yet does not count, and the reason says when it will" do
    awards = [award(10, @rope, starts_at: ~U[2026-10-01 00:00:00Z])]

    assert plan([[@rope]], awards, [member(10)]).remove == %{
             10 => [{:not_started, @rope, ~U[2026-10-01 00:00:00Z]}]
           }
  end

  test "an expired award still counts when another award for it is active" do
    awards = [award(10, @rope, ends_at: ~U[2026-09-01 00:00:00Z]), award(10, @rope)]

    assert plan([[@rope]], awards, [member(10)]).remove == %{}
  end

  test "a member who has left is removed for that reason alone and never added" do
    left_at = ~U[2026-08-01 00:00:00Z]

    awards = [
      award(10, @rope, member_left_at: left_at),
      award(11, @rope, member_left_at: left_at)
    ]

    result = plan([[@rope], [@first_aid]], awards, [member(10, left_at)])

    assert result.add == MapSet.new()
    assert result.remove == %{10 => [{:left, left_at}]}
  end

  test "every unmet clause gives a reason, and a missing one names the whole clause" do
    awards = [award(12, @first_aid, ends_at: ~U[2026-01-15 00:00:00Z])]

    result = plan([[@rope, @swiftwater], [@first_aid]], awards, [member(12)])

    assert result.remove == %{
             12 => [
               {:missing, [@rope, @swiftwater]},
               {:expired, @first_aid, ~U[2026-01-15 00:00:00Z]}
             ]
           }
  end

  test "a member whose award ends within 60 days is expiring" do
    awards = [
      award(10, @rope, ends_at: ~U[2026-10-02 00:00:00Z]),
      award(11, @rope, ends_at: ~U[2026-12-01 00:00:00Z])
    ]

    result = plan([[@rope]], awards, [member(10), member(11)])

    assert result.expiring == %{
             10 => %{d4h_qualification_id: @rope, ends_at: ~U[2026-10-02 00:00:00Z]}
           }
  end

  test "a renewal on record, even one not started yet, means not expiring" do
    awards = [
      award(10, @rope, ends_at: ~U[2026-10-02 00:00:00Z]),
      award(10, @rope, starts_at: ~U[2026-10-02 00:00:00Z], ends_at: ~U[2028-10-02 00:00:00Z]),
      award(11, @rope, ends_at: ~U[2026-10-02 00:00:00Z]),
      award(11, @swiftwater)
    ]

    result = plan([[@rope, @swiftwater]], awards, [member(10), member(11)])

    assert result.expiring == %{}
  end

  test "the clause that runs out first is the one expiring" do
    awards = [
      award(10, @rope, ends_at: ~U[2026-11-01 00:00:00Z]),
      award(10, @first_aid, ends_at: ~U[2026-10-01 00:00:00Z])
    ]

    result = plan([[@rope], [@first_aid]], awards, [member(10)])

    assert result.expiring == %{
             10 => %{d4h_qualification_id: @first_aid, ends_at: ~U[2026-10-01 00:00:00Z]}
           }
  end

  test "an empty clause plans no changes instead of removing everyone" do
    result = plan([[@rope], []], [award(10, @rope)], [member(11), member(12)])

    assert result.add == MapSet.new()
    assert result.remove == %{}
  end

  test "no clauses plans no changes" do
    result = plan([], [award(10, @rope)], [member(11)])

    assert result.add == MapSet.new()
    assert result.remove == %{}
  end

  test "a qualification with no local row is reported once" do
    missing = BuildGroupRulePreview.missing_qualification_ids([[@rope, 99], [99]], [@rope])

    assert missing == [99]
  end

  test "reasons read as short sentences in the team's time zone" do
    titles = %{@rope => "Rope", @swiftwater => "Swiftwater"}
    describe = &BuildGroupRulePreview.describe(&1, titles, "America/Vancouver")

    assert describe.({:missing, [@rope, @swiftwater]}) == "No Rope or Swiftwater on record"
    assert describe.({:expired, @rope, ~U[2026-04-01 03:00:00Z]}) == "Rope expired Mar 31, 2026"
    assert describe.({:left, ~U[2026-02-12 20:00:00Z]}) == "Left the team Feb 12, 2026"
  end
end
