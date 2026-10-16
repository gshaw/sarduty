defmodule App.Operation.PlanGroupRules do
  @moduledoc """
  Turns one team's group endorsements and the groups they start from into In rules, for
  the migration that introduces them (#334). Every group keeps a rule that admits exactly
  the same members.

  - Each endorsement in a group's rule becomes `In: <endorsement>`.
  - The group a group starts from becomes `In: <parent>`, first. The parent's members are
    then whoever meets its rules, the same set its endorsements gave before.
  - A parent that adds nothing today is dropped: one no longer in D4H, one with no rule
    anywhere up its chain, and one in a loop. As an In rule it would count its D4H list
    or break the rule.

  Delete this module with the old `group_endorsements` and `group_parents` tables.
  """

  @doc """
  Pure. `group_endorsements` are `{d4h_group_id, endorsement_id}` in the order they were
  added, `parents` maps a D4H group id to its parent's, and `group_ids` are the D4H ids of
  the groups D4H still has. Returns the rules as `{d4h_group_id, {:group | :endorsement,
  id}}` in the order to insert them, and the parents dropped with why.
  """
  def plan(group_endorsements, parents, group_ids) do
    group_ids = MapSet.new(group_ids)
    own = Enum.group_by(group_endorsements, &elem(&1, 0), &elem(&1, 1))
    children = parents |> Map.keys() |> Enum.sort()

    checked = Enum.map(children, &{&1, parents[&1], why_dropped(&1, parents, own, group_ids)})
    %{rules: rules(checked, group_endorsements), dropped: dropped(checked)}
  end

  defp rules(checked, group_endorsements),
    do:
      for({g, p, nil} <- checked, do: {g, {:group, p}}) ++
        for({g, id} <- group_endorsements, do: {g, {:endorsement, id}})

  defp dropped(checked),
    do: for({g, p, why} <- checked, why, do: %{d4h_group_id: g, parent: p, why: why})

  defp why_dropped(g, parents, own, group_ids) do
    parent = parents[g]

    cond do
      not MapSet.member?(group_ids, parent) -> :not_in_d4h
      loop?(g, parents) -> :loop
      not ruled?(parent, parents, own, group_ids, [g]) -> :no_rules
      true -> nil
    end
  end

  defp loop?(g, parents), do: climb(parents[g], parents, [g]) == :loop

  defp climb(nil, _parents, _seen), do: :ok

  defp climb(id, parents, seen),
    do: if(id in seen, do: :loop, else: climb(parents[id], parents, [id | seen]))

  # True when the group, or a group up its chain that D4H still has, names an endorsement.
  defp ruled?(g, parents, own, group_ids, seen) do
    cond do
      Map.has_key?(own, g) ->
        true

      g in seen ->
        false

      (p = parents[g]) && MapSet.member?(group_ids, p) ->
        ruled?(p, parents, own, group_ids, [g | seen])

      true ->
        false
    end
  end
end
