defmodule App.Operation.BuildCardQualificationsTest do
  use ExUnit.Case, async: true

  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Operation.BuildCardQualifications

  @now ~U[2026-09-30 12:00:00Z]

  defp clause(name, ids) do
    %GroupRuleClause{
      name: name,
      group_rule_clause_qualifications:
        Enum.map(ids, &%GroupRuleClauseQualification{d4h_qualification_id: &1})
    }
  end

  defp award(id, starts_at, ends_at),
    do: %{d4h_qualification_id: id, starts_at: starts_at, ends_at: ends_at}

  test "a clause is current until the latest end among its active awards" do
    awards = [
      award(1, ~U[2025-01-01 00:00:00Z], ~U[2026-11-15 00:00:00Z]),
      award(2, ~U[2025-06-01 00:00:00Z], ~U[2027-05-01 00:00:00Z])
    ]

    assert [%{name: "First Aid", ends_at: ~U[2027-05-01 00:00:00Z]}] =
             BuildCardQualifications.summarize([clause("First Aid", [1, 2])], awards, @now)
  end

  test "an award with no end means no expiry" do
    awards = [award(1, nil, ~U[2027-01-01 00:00:00Z]), award(2, nil, nil)]

    assert [%{name: "Tracking", ends_at: nil}] =
             BuildCardQualifications.summarize([clause("Tracking", [1, 2])], awards, @now)
  end

  test "expired, future, and missing awards leave the clause off" do
    awards = [
      award(1, nil, ~U[2026-01-01 00:00:00Z]),
      award(2, ~U[2027-01-01 00:00:00Z], nil)
    ]

    assert [] = BuildCardQualifications.summarize([clause("Rope", [1, 2, 3])], awards, @now)
  end

  test "clauses with the same name count once, met by any of their qualifications" do
    clauses = [clause("First Aid", [1]), clause("First Aid", [2]), clause("Avalanche", [3])]
    awards = [award(2, nil, nil)]

    assert [%{name: "First Aid"}] = BuildCardQualifications.summarize(clauses, awards, @now)
  end

  test "describe gives one line per qualification in the team's time zone" do
    tz = "America/Vancouver"

    assert BuildCardQualifications.describe(
             %{name: "First Aid", ends_at: ~U[2026-11-15 07:00:00Z]},
             tz
           ) == "First Aid — expires Nov 2026"

    assert BuildCardQualifications.describe(
             %{name: "Tracking", ends_at: nil},
             tz
           ) ==
             "Tracking — no expiry"
  end
end
