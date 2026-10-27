defmodule App.Operation.AddGroupRule do
  @moduledoc """
  Adds a group, endorsement, or standing to a group's rules (#334, #366): as a new rule
  of `kind` (`:in`, `:not_in`, or `:standing`), or to an existing rule. A standing joins
  the group's Standing rule if it has one, since two would need a member to have both. A
  group that would make a loop is left out. `{:error, message}` when the target doesn't
  fit the rule's kind, or the group is the team's Retiring group (#514), whose rules would
  take its members out.

  The group and rule come looked up through the team, and the target from
  `App.ViewData.GroupRules.find_target!/2`.
  """

  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.GroupRuleReference
  alias App.Model.Team
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo

  def call(%Group{} = group, kind_or_rule, target) do
    kind = if is_struct(kind_or_rule, GroupRule), do: kind_or_rule.kind, else: kind_or_rule
    rules = GroupRule.get_all(group.team_id)

    with :ok <- not_retiring(group),
         :ok <- fits(kind, target) do
      unless loop?(rules, group, target), do: add(group, kind_or_rule, target, rules)
      :ok
    end
  end

  defp not_retiring(group) do
    if Repo.get!(Team, group.team_id).retiring_d4h_group_id == group.d4h_group_id,
      do: {:error, "Members of this group are retiring. It cannot have group rules."},
      else: :ok
  end

  defp fits(:standing, {:standing, _standing}), do: :ok
  defp fits(:standing, _target), do: {:error, "Select a standing for a Standing is rule."}

  defp fits(_kind, {:standing, _standing}),
    do: {:error, "Select a group or endorsement for an In or Not in rule."}

  defp fits(_kind, _target), do: :ok

  defp loop?(rules, group, %Group{d4h_group_id: other}) do
    named? =
      rules
      |> BuildGroupRulePreview.rules_by_group()
      |> GroupRule.can_name?(group.d4h_group_id, other)

    not named?
  end

  defp loop?(_rules, _group, _target), do: false

  defp add(_group, %GroupRule{} = rule, target, _rules),
    do: GroupRuleReference.add!(rule, unwrap(target))

  defp add(group, :standing, {:standing, standing}, rules) do
    case Enum.find(rules, &(&1.d4h_group_id == group.d4h_group_id and &1.kind == :standing)) do
      nil -> GroupRule.add!(group, :standing, standing)
      rule -> GroupRuleReference.add!(rule, standing)
    end
  end

  defp add(group, kind, target, _rules), do: GroupRule.add!(group, kind, target)

  defp unwrap({:standing, standing}), do: standing
  defp unwrap(target), do: target
end
