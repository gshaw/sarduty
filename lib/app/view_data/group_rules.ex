defmodule App.ViewData.GroupRules do
  alias App.Model.Endorsement
  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Repo

  # What a group's page and a rule's page show about rules (#334), from the context
  # `BuildGroupRulePreview.load/1` builds. A group D4H no longer has reads by its id.

  @doc "Pure. The rule as `%{kind, names}` for `rule_sentence/1`."
  def named(rule, context),
    do: %{kind: rule.kind, names: Enum.map(rule.targets, &{elem(&1, 0), name(&1, context)})}

  @doc "Pure. The name of a group or endorsement in a rule."
  def name({:group, g}, context) do
    case context.groups[g] do
      nil -> "a group no longer in D4H (#{g})"
      group -> group.title
    end
  end

  def name({:endorsement, id}, context), do: context.endorsements[id].name
  def name({:standing, standing}, _context), do: standing_label(standing)

  @standings [active: "Active", away: "Away", not_a_person: "Not a person"]

  @doc "A standing's name in a rule (#366)."
  def standing_label(standing), do: Keyword.fetch!(@standings, standing)

  @doc "Pure. The menu's standings for a Standing rule, leaving out `taken`."
  def standing_options(taken \\ []) do
    for {standing, label} <- @standings,
        {:standing, standing} not in taken,
        do: {label, "standing:#{standing}"}
  end

  @doc """
  Pure. Whether the editor suggests "Standing is Active": the group has rules, and none
  is a Standing rule. It is a suggestion, never added for the team.
  """
  def suggest_standing?(rules), do: rules != [] and not Enum.any?(rules, &(&1.kind == :standing))

  @doc """
  Pure. Each group the rules name, once, in order: `{:smart, group, rules}` for one with
  rules, `{:list, group}` for one without, or `{:missing, d4h_group_id}`.
  """
  def referenced_groups(rules, context) do
    for rule <- rules, {:group, g} <- rule.targets, uniq: true do
      case {context.groups[g], Map.get(context.rules, g, [])} do
        {nil, _rules} -> {:missing, g}
        {group, []} -> {:list, group}
        {group, rules} -> {:smart, group, Enum.map(rules, &named(&1, context))}
      end
    end
  end

  @doc """
  Pure. The menu of groups and endorsements a rule on group `d4h_group_id` can add, as
  `{label, [{name, value}]}`, leaving out `taken` and any group that would make a loop.
  """
  def options(context, d4h_group_id, taken \\ []) do
    groups =
      for {g, group} <- context.groups,
          {:group, g} not in taken,
          GroupRule.can_name?(context.rules, d4h_group_id, g),
          do: {group.title, "group:#{group.id}"}

    endorsements =
      for {id, e} <- context.endorsements,
          {:endorsement, id} not in taken,
          do: {e.name, "endorsement:#{id}"}

    [{"Groups", Enum.sort(groups)}, {"Endorsements", Enum.sort(endorsements)}]
    |> Enum.reject(fn {_label, options} -> options == [] end)
  end

  @doc """
  The group or endorsement a menu value names, looked up through the team. Raises for
  one of another team, as a page load would.
  """
  def find_target!(team_id, "group:" <> id),
    do: Repo.get_by!(Group, id: String.to_integer(id), team_id: team_id)

  def find_target!(team_id, "endorsement:" <> id),
    do: Endorsement.get!(team_id, String.to_integer(id))

  def find_target!(_team_id, "standing:" <> standing) do
    case Enum.find(@standings, fn {key, _label} -> Atom.to_string(key) == standing end) do
      {key, _label} -> {:standing, key}
      nil -> raise Ecto.NoResultsError, queryable: App.Model.GroupRuleReference
    end
  end

  @doc """
  Pure. The warning before a change flips whether the group counts by its rules or by its
  D4H list, for the groups whose rules name it, or nil when none do.
  """
  def flip_warning(context, d4h_group_id, change) do
    titles =
      context.rules
      |> GroupRule.used_by(d4h_group_id)
      |> Enum.map(&context.groups[&1])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.title)
      |> Enum.sort()

    case {titles, change} do
      {[], _change} ->
        nil

      {[one], :first_rule} ->
        "#{one} uses this group's list. Once it has rules, #{one} uses its rules instead."

      {many, :first_rule} ->
        "#{and_list(many)} use this group's list. Once it has rules, they use its rules instead."

      {[one], :last_rule} ->
        "#{one} uses this group's rules. Without them, #{one} uses its list in D4H instead."

      {many, :last_rule} ->
        "#{and_list(many)} use this group's rules. Without them, they use its list in D4H instead."
    end
  end

  defp and_list([a, b]), do: "#{a} and #{b}"
  defp and_list(many), do: "#{many |> Enum.drop(-1) |> Enum.join(", ")}, and #{List.last(many)}"
end
