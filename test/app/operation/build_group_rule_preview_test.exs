defmodule App.Operation.BuildGroupRulePreviewTest do
  use ExUnit.Case, async: true

  alias App.Operation.BuildGroupRulePreview

  @now ~U[2026-09-10 12:00:00Z]

  # Qualifications, by D4H id.
  @rope 1
  @swiftwater 2
  @first_aid 3

  # Endorsements, by id.
  @rope_e 101
  @water_e 102
  @first_aid_e 103

  # Groups, by D4H id. @callout is the group being planned.
  @callout 1000
  @gsar 1001
  @loa 1002
  @mit 1003

  defp award(member_id, qualification_id, attrs \\ []) do
    Map.merge(
      %{
        member_id: member_id,
        d4h_qualification_id: qualification_id,
        starts_at: ~U[2025-01-01 00:00:00Z],
        ends_at: nil
      },
      Map.new(attrs)
    )
  end

  defp member(id, left_at \\ nil), do: %{id: id, left_at: left_at}

  defp rule(kind, targets), do: %{id: System.unique_integer(), kind: kind, targets: targets}
  defp in_rule(targets), do: rule(:in, targets)
  defp not_in(targets), do: rule(:not_in, targets)

  # `rules` are the planned group's; `opts` give other groups' rules, every group's D4H
  # members, the awards, and the team's members (ids 10 to 19 unless given).
  defp context(rules, opts \\ []) do
    %{
      rules: opts |> Keyword.get(:rules, %{}) |> Map.put(@callout, rules),
      groups: groups(Keyword.get(opts, :lists, %{}), Keyword.get(opts, :deleted, [])),
      endorsements: %{
        @rope_e => %{name: "Rope", qualification_ids: [@rope]},
        @water_e => %{name: "Water", qualification_ids: [@rope, @swiftwater]},
        @first_aid_e => %{name: "First Aid", qualification_ids: [@first_aid]}
      },
      titles: %{@rope => "Rope 1", @swiftwater => "Swiftwater 1", @first_aid => "OFA 1"},
      awards_by_member: opts |> Keyword.get(:awards, []) |> Enum.group_by(& &1.member_id),
      members: Keyword.get(opts, :members, Enum.map(10..19, &member/1))
    }
    |> Map.merge(Keyword.get(opts, :override, %{}))
  end

  defp groups(lists, deleted) do
    for {g, title} <- [{@callout, "Callout"}, {@gsar, "GSAR"}, {@loa, "LOA"}, {@mit, "MIT"}],
        g not in deleted,
        into: %{},
        do: {g, %{id: g, title: title, member_ids: lists |> Map.get(g, []) |> MapSet.new()}}
  end

  defp plan(context), do: BuildGroupRulePreview.plan(context, @callout, @now)
  defp problems(context), do: BuildGroupRulePreview.problems(context, @callout)

  describe "In rules" do
    test "a member must meet every rule" do
      awards = [award(10, @rope), award(10, @first_aid), award(11, @rope)]
      rules = [in_rule([{:endorsement, @rope_e}]), in_rule([{:endorsement, @first_aid_e}])]

      assert plan(context(rules, awards: awards)).add == MapSet.new([10])
    end

    test "any group or endorsement in a rule meets it" do
      awards = [award(10, @rope)]
      rules = [in_rule([{:endorsement, @first_aid_e}, {:endorsement, @rope_e}, {:group, @loa}])]

      result = plan(context(rules, awards: awards, lists: %{@loa => [11]}))

      assert result.add == MapSet.new([10, 11])
    end

    test "a group without rules counts by its D4H list" do
      result =
        plan(context([in_rule([{:group, @loa}])], lists: %{@loa => [12], @callout => [13]}))

      assert result.add == MapSet.new([12])
      assert result.remove == %{13 => [{:none_of, ["LOA"], []}]}
    end

    test "a group with rules counts by its rules, never its D4H list" do
      awards = [award(10, @rope)]

      result =
        plan(
          context([in_rule([{:group, @gsar}])],
            awards: awards,
            rules: %{@gsar => [in_rule([{:endorsement, @rope_e}])]},
            lists: %{@gsar => [11], @callout => [11]}
          )
        )

      assert result.add == MapSet.new([10])
      assert result.remove == %{11 => [{:none_of, [], ["Rope"]}]}
    end

    test "groups built from groups follow each one's rules" do
      awards = [award(10, @rope), award(10, @first_aid), award(11, @rope)]

      result =
        plan(
          context([in_rule([{:group, @mit}])],
            awards: awards,
            rules: %{
              @mit => [in_rule([{:group, @gsar}]), in_rule([{:endorsement, @first_aid_e}])],
              @gsar => [in_rule([{:endorsement, @rope_e}])]
            },
            lists: %{@callout => [11]}
          )
        )

      assert result.add == MapSet.new([10])
      assert result.remove == %{11 => [{:none_of, [], ["First Aid"]}]}
    end
  end

  describe "Not in rules" do
    test "take out members of a group or holders of an endorsement" do
      awards = [award(10, @rope), award(11, @rope), award(12, @rope), award(12, @first_aid)]

      rules = [
        in_rule([{:endorsement, @rope_e}]),
        not_in([{:group, @loa}, {:endorsement, @first_aid_e}])
      ]

      result = plan(context(rules, awards: awards, lists: %{@loa => [11], @callout => [11, 12]}))

      assert result.add == MapSet.new([10])
      assert result.remove == %{11 => [{:in, "LOA"}], 12 => [{:holds, "First Aid"}]}
    end

    test "never make a member expiring" do
      awards = [award(10, @rope), award(11, @first_aid, ends_at: ~U[2026-09-01 00:00:00Z])]

      rules = [in_rule([{:endorsement, @rope_e}]), not_in([{:endorsement, @first_aid_e}])]

      assert plan(context(rules, awards: awards)).expiring == %{}
    end
  end

  describe "reasons" do
    test "an expired award does not count, and the reason says when it ended" do
      awards = [
        award(10, @rope, ends_at: ~U[2026-09-01 00:00:00Z]),
        award(11, @rope, ends_at: ~U[2027-01-01 00:00:00Z])
      ]

      result =
        plan(
          context([in_rule([{:endorsement, @rope_e}])],
            awards: awards,
            lists: %{@callout => [10, 11]}
          )
        )

      assert result.add == MapSet.new()
      assert result.remove == %{10 => [{:expired, @rope, ~U[2026-09-01 00:00:00Z]}]}
    end

    test "the reason names the most recent of several expired awards" do
      awards = [
        award(10, @rope, ends_at: ~U[2024-09-01 00:00:00Z]),
        award(10, @rope, ends_at: ~U[2026-09-01 00:00:00Z])
      ]

      result =
        plan(
          context([in_rule([{:endorsement, @rope_e}])],
            awards: awards,
            lists: %{@callout => [10]}
          )
        )

      assert result.remove == %{10 => [{:expired, @rope, ~U[2026-09-01 00:00:00Z]}]}
    end

    test "an award that has not started does not count, and the reason says when it will" do
      awards = [award(10, @rope, starts_at: ~U[2026-10-01 00:00:00Z])]

      result =
        plan(
          context([in_rule([{:endorsement, @rope_e}])],
            awards: awards,
            lists: %{@callout => [10]}
          )
        )

      assert result.remove == %{10 => [{:not_started, @rope, ~U[2026-10-01 00:00:00Z]}]}
    end

    test "an expired award still counts when another for it is active" do
      awards = [award(10, @rope, ends_at: ~U[2026-09-01 00:00:00Z]), award(10, @rope)]

      result =
        plan(
          context([in_rule([{:endorsement, @rope_e}])],
            awards: awards,
            lists: %{@callout => [10]}
          )
        )

      assert result.remove == %{}
    end

    test "a member who has left is removed for that reason alone and never added" do
      left_at = ~U[2026-08-01 00:00:00Z]
      awards = [award(10, @rope), award(11, @rope)]

      result =
        plan(
          context([in_rule([{:endorsement, @rope_e}])],
            awards: awards,
            members: [member(10, left_at), member(11, left_at)],
            lists: %{@callout => [10]}
          )
        )

      assert result.add == MapSet.new()
      assert result.remove == %{10 => [{:left, left_at}]}
    end

    test "every unmet rule gives a reason, and a rule of several names them all" do
      awards = [award(12, @first_aid, ends_at: ~U[2026-01-15 00:00:00Z])]

      rules = [
        in_rule([{:group, @gsar}, {:group, @mit}]),
        in_rule([{:endorsement, @rope_e}, {:endorsement, @water_e}]),
        in_rule([{:endorsement, @first_aid_e}])
      ]

      result = plan(context(rules, awards: awards, lists: %{@callout => [12]}))

      assert result.remove == %{
               12 => [
                 {:none_of, ["GSAR", "MIT"], []},
                 {:none_of, [], ["Rope", "Water"]},
                 {:expired, @first_aid, ~U[2026-01-15 00:00:00Z]}
               ]
             }
    end

    test "a group with rules gives its own unmet reasons" do
      result =
        plan(
          context([in_rule([{:group, @gsar}])],
            rules: %{@gsar => [in_rule([{:endorsement, @rope_e}])]},
            lists: %{@callout => [10]}
          )
        )

      assert result.remove == %{10 => [{:none_of, [], ["Rope"]}]}
    end

    test "read as short sentences in the team's time zone" do
      titles = %{@rope => "Rope 1"}
      describe = &BuildGroupRulePreview.describe(&1, titles, "America/Vancouver")

      assert describe.({:none_of, [], ["First Aid 16 hours", "MIT Callout Approval"]}) ==
               "No First Aid 16 hours or MIT Callout Approval on record"

      assert describe.({:none_of, ["GSAR Qualified Callout", "MIT Callout"], []}) ==
               "Not in GSAR Qualified Callout or MIT Callout"

      assert describe.({:none_of, ["Rope Rescue"], ["Rope"]}) ==
               "Not in Rope Rescue, and no Rope on record"

      assert describe.({:in, "LOA"}) == "In LOA"
      assert describe.({:holds, "First Aid 16 hours"}) == "Holds First Aid 16 hours"

      assert describe.({:expired, @rope, ~U[2026-04-01 03:00:00Z]}) ==
               "Rope 1 expired Mar 31, 2026"

      assert describe.({:left, ~U[2026-02-12 20:00:00Z]}) == "Left the team Feb 12, 2026"
    end
  end

  describe "expiring" do
    test "a member whose award ends within 60 days" do
      awards = [
        award(10, @rope, ends_at: ~U[2026-10-02 00:00:00Z]),
        award(11, @rope, ends_at: ~U[2026-12-01 00:00:00Z])
      ]

      result = plan(context([in_rule([{:endorsement, @rope_e}])], awards: awards))

      assert result.expiring == %{
               10 => %{d4h_qualification_id: @rope, ends_at: ~U[2026-10-02 00:00:00Z]}
             }
    end

    test "a renewal on record, even one not started, or another way in means not expiring" do
      awards = [
        award(10, @rope, ends_at: ~U[2026-10-02 00:00:00Z]),
        award(10, @rope, starts_at: ~U[2026-10-02 00:00:00Z], ends_at: ~U[2028-10-02 00:00:00Z]),
        award(11, @rope, ends_at: ~U[2026-10-02 00:00:00Z]),
        award(11, @swiftwater),
        award(12, @first_aid, ends_at: ~U[2026-10-02 00:00:00Z])
      ]

      rules = [in_rule([{:endorsement, @water_e}, {:group, @loa}, {:endorsement, @first_aid_e}])]

      assert plan(context(rules, awards: awards, lists: %{@loa => [12]})).expiring == %{}
    end

    test "the rule that runs out first is the one expiring, through groups too" do
      awards = [
        award(10, @rope, ends_at: ~U[2026-11-01 00:00:00Z]),
        award(10, @first_aid, ends_at: ~U[2026-10-01 00:00:00Z])
      ]

      result =
        plan(
          context([in_rule([{:endorsement, @rope_e}]), in_rule([{:group, @gsar}])],
            awards: awards,
            rules: %{@gsar => [in_rule([{:endorsement, @first_aid_e}])]}
          )
        )

      assert result.expiring == %{
               10 => %{d4h_qualification_id: @first_aid, ends_at: ~U[2026-10-01 00:00:00Z]}
             }
    end
  end

  describe "problems plan no changes" do
    test "no rules, or only Not in rules" do
      assert problems(context([])) == [:no_rules]

      only_not_in = context([not_in([{:group, @loa}])], lists: %{@callout => [10]})
      assert problems(only_not_in) == [:no_in_rule]
      assert plan(only_not_in) == %{add: MapSet.new(), remove: %{}, expiring: %{}}
    end

    test "a rule with nothing in it" do
      ctx = context([in_rule([{:group, @loa}]), not_in([])], lists: %{@loa => [10]})

      assert problems(ctx) == [:empty_rule]
      assert plan(ctx).add == MapSet.new()
    end

    test "an endorsement nothing earns, or one naming a qualification D4H dropped" do
      endorsements = %{
        @rope_e => %{name: "Rope", qualification_ids: []},
        @water_e => %{name: "Water", qualification_ids: [@rope, 99]}
      }

      ctx =
        context([in_rule([{:endorsement, @rope_e}]), not_in([{:endorsement, @water_e}])],
          override: %{endorsements: endorsements}
        )

      assert problems(ctx) == [{:empty_endorsement, "Rope"}, {:missing_qualification, "Water"}]
    end

    test "a group D4H dropped, even in a Not in rule" do
      ctx =
        context([in_rule([{:endorsement, @rope_e}]), not_in([{:group, @loa}])],
          awards: [award(10, @rope)],
          deleted: [@loa]
        )

      assert problems(ctx) == [{:missing_group, @loa}]
      assert plan(ctx).add == MapSet.new()
    end

    test "a group whose own rules are broken" do
      ctx =
        context([in_rule([{:group, @gsar}])],
          rules: %{@gsar => [not_in([{:group, @loa}])]}
        )

      assert problems(ctx) == [{:broken_group, "GSAR"}]
    end

    test "a loop already in the data stops" do
      ctx =
        context([in_rule([{:group, @gsar}])],
          rules: %{@gsar => [in_rule([{:group, @mit}])], @mit => [in_rule([{:group, @callout}])]}
        )

      assert problems(ctx) == [{:loop, "Callout"}]

      assert problems(%{
               ctx
               | rules: Map.put(ctx.rules, @callout, [in_rule([{:group, @callout}])])
             }) ==
               [{:loop, "Callout"}]
    end
  end
end
