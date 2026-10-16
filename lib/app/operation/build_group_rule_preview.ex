defmodule App.Operation.BuildGroupRulePreview do
  import Ecto.Query

  alias App.Model.Endorsement
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  # Matches D4H's default reminder before a qualification expires.
  @expiring_days 60

  def expiring_days, do: @expiring_days

  # A group's rules are a list, and a member must meet every one (#334). An In rule is met
  # by being in any of its groups or holding any of its endorsements, and a Not in rule by
  # none of them. A group with rules counts whoever meets them; one without counts its D4H
  # list. `plan/3` works on a context of plain maps, so it needs no database:
  #
  # - `rules`: each D4H group id with its rules, `%{id, kind, targets}`, where a target is
  #   `{:group, d4h_group_id}` or `{:endorsement, id}`.
  # - `groups`: each D4H group id D4H still has, with `%{id, title, member_ids}`.
  # - `endorsements`: each id with `%{name, qualification_ids}`, includes followed.
  # - `titles`: each qualification D4H still has, by D4H id.
  # - `awards_by_member`: each member id with their awards for those qualifications.
  # - `members`: the team's members, each with `id` and `left_at`.

  @doc "The team's context for `plan/3`."
  def load(%Team{} = team) do
    endorsements = Endorsement.get_all(team.id)

    %{
      rules: team.id |> GroupRule.get_all() |> rules_by_group(),
      groups: load_groups(team.id),
      endorsements: Map.new(endorsements, &{&1.id, endorsement_entry(&1)}),
      titles: team.id |> Qualification.get_all() |> Map.new(&{&1.d4h_qualification_id, &1.title}),
      awards_by_member: awards_by_member(team.id, endorsements),
      members: list_team_members(team.id)
    }
  end

  defp awards_by_member(team_id, endorsements) do
    ids = endorsements |> Enum.flat_map(&Endorsement.qualification_ids/1) |> Enum.uniq()
    team_id |> list_awards(ids) |> Enum.group_by(& &1.member_id)
  end

  defp list_team_members(team_id) do
    Member
    |> where([m], m.team_id == ^team_id)
    |> select([m], map(m, [:id, :left_at]))
    |> Repo.all()
  end

  defp endorsement_entry(endorsement),
    do: %{name: endorsement.name, qualification_ids: Endorsement.qualification_ids(endorsement)}

  @doc "Pure. Each D4H group id with its rules in the shape `plan/3` takes."
  def rules_by_group(rules) do
    rules
    |> GroupRule.by_group()
    |> Map.new(fn {g, rs} ->
      {g, Enum.map(rs, &%{id: &1.id, kind: &1.kind, targets: GroupRule.targets(&1)})}
    end)
  end

  defp load_groups(team_id) do
    member_ids =
      GroupMember
      |> join(:inner, [gm], g in assoc(gm, :group))
      |> where([gm, g], g.team_id == ^team_id)
      |> select([gm, g], {g.id, gm.member_id})
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for group <- Group.get_all(team_id), into: %{} do
      {group.d4h_group_id,
       %{
         id: group.id,
         title: group.title,
         member_ids: member_ids |> Map.get(group.id, []) |> MapSet.new()
       }}
    end
  end

  @doc """
  The group's preview: its problems, the members to add, the members to remove with why,
  and the members who qualify now but won't within #{@expiring_days} days, each a row with
  the member and a reason as text. Rules with a problem plan no changes.
  """
  def for_group(%Team{} = team, %Group{} = group, now \\ DateTime.utc_now()),
    do: team |> load() |> preview(team, group, now)

  def preview(context, %Team{} = team, %Group{} = group, now \\ DateTime.utc_now()) do
    case problems(context, group.d4h_group_id) do
      [] ->
        plan = plan(context, group.d4h_group_id, now)
        build_preview(plan, &describe(&1, context.titles, team.timezone), now)

      problems ->
        %{problems: problems, to_add: [], to_remove: [], expiring: []}
    end
  end

  @doc """
  Pure. Why the group's rules can't plan changes, or `[]` when they can. Each of these
  would otherwise add every member or remove them all:

  - `:no_rules`, or `:no_in_rule` when every rule is Not in.
  - `:empty_rule`, a rule with no groups or endorsements.
  - `{:empty_endorsement, name}`: nothing earns it.
  - `{:missing_qualification, name}`: it names a qualification D4H no longer has.
  - `{:missing_group, d4h_group_id}`: a group D4H no longer has.
  - `{:broken_group, title}`: a group whose own rules have a problem.
  - `{:loop, title}`: a group that leads back to one already being worked out.
  """
  def problems(context, d4h_group_id),
    do: d4h_group_id |> check_rules(context, []) |> Enum.uniq()

  defp check_rules(g, context, stack) do
    rules = Map.get(context.rules, g, [])

    cond do
      rules == [] -> [:no_rules]
      not Enum.any?(rules, &(&1.kind == :in)) -> [:no_in_rule]
      true -> Enum.flat_map(rules, &check_rule(&1, context, [g | stack]))
    end
  end

  defp check_rule(%{targets: []}, _context, _stack), do: [:empty_rule]

  defp check_rule(rule, context, stack),
    do: Enum.flat_map(rule.targets, &check_target(&1, context, stack))

  defp check_target({:endorsement, id}, context, _stack) do
    known = context.titles

    case context.endorsements[id] do
      nil ->
        [:empty_rule]

      %{qualification_ids: []} = e ->
        [{:empty_endorsement, e.name}]

      e ->
        if Enum.all?(e.qualification_ids, &Map.has_key?(known, &1)),
          do: [],
          else: [{:missing_qualification, e.name}]
    end
  end

  defp check_target({:group, g}, context, stack) do
    group = context.groups[g]

    cond do
      is_nil(group) -> [{:missing_group, g}]
      g in stack -> [{:loop, group.title}]
      Map.get(context.rules, g, []) == [] -> []
      true -> nested_problems(check_rules(g, context, stack), group)
    end
  end

  defp nested_problems([], _group), do: []

  defp nested_problems(problems, group) do
    case Enum.filter(problems, &match?({:loop, _}, &1)) do
      [] -> [{:broken_group, group.title}]
      loops -> loops
    end
  end

  @doc """
  Pure. The member ids to add, the members to remove with their reasons, and the members
  who qualify now but won't within #{@expiring_days} days, with the award that runs out.
  Only current members are added. Rules with a problem plan nothing.
  """
  def plan(context, d4h_group_id, now) do
    if problems(context, d4h_group_id) == [] do
      {statuses, _memo} = group_statuses(d4h_group_id, context, now, %{})
      in_group = context.groups[d4h_group_id].member_ids
      qualifying = qualifying_ids(context.members, statuses, now)

      %{
        add: MapSet.difference(qualifying, in_group),
        remove: removals(in_group, qualifying, statuses, context, now),
        expiring: expiring(qualifying, statuses, now)
      }
    else
      %{add: MapSet.new(), remove: %{}, expiring: %{}}
    end
  end

  defp qualifying_ids(members, statuses, now) do
    for m <- members,
        Member.current?(m, now),
        match?({:met, _}, statuses[m.id]),
        into: MapSet.new(),
        do: m.id
  end

  defp removals(in_group, qualifying, statuses, context, now) do
    members = Map.new(context.members, &{&1.id, &1})

    for id <- in_group, not MapSet.member?(qualifying, id), into: %{} do
      {id, removal_reasons(members[id], statuses[id], now)}
    end
  end

  defp removal_reasons(member, status, now) do
    cond do
      member && not Member.current?(member, now) -> [{:left, member.left_at}]
      match?({:unmet, _}, status) -> elem(status, 1)
      true -> []
    end
  end

  defp expiring(qualifying, statuses, now) do
    cutoff = DateTime.add(now, @expiring_days, :day)

    for id <- qualifying,
        {:met, %{ends_at: ends_at} = award} <- [statuses[id]],
        DateTime.before?(ends_at, cutoff),
        into: %{},
        do: {id, award}
  end

  # Each member's status in a group, a rule, or a target: `{:met, ends}` or
  # `{:unmet, reasons}`. `ends` is the award that runs out first, or nil when nothing
  # does. A group's statuses are worked out once and kept in `memo`.
  defp group_statuses(g, context, now, memo) do
    case Map.fetch(memo, {:group, g}) do
      {:ok, statuses} ->
        {statuses, memo}

      :error ->
        {rules, memo} =
          Enum.map_reduce(context.rules[g], memo, &rule_targets(&1, context, now, &2))

        statuses =
          Map.new(context.members, fn m ->
            {m.id, all_rules(Enum.map(rules, &rule_status(&1, m.id, context)))}
          end)

        {statuses, Map.put(memo, {:group, g}, statuses)}
    end
  end

  # The rule's kind, and each of its targets with every member's status in it.
  defp rule_targets(rule, context, now, memo) do
    {targets, memo} =
      Enum.map_reduce(rule.targets, memo, fn target, memo ->
        {statuses, memo} = target_statuses(target, context, now, memo)
        {{target, statuses}, memo}
      end)

    {{rule.kind, targets}, memo}
  end

  defp target_statuses({:group, g} = target, context, now, memo) do
    if Map.get(context.rules, g, []) == [],
      do: {list_statuses(target, context), memo},
      else: group_statuses(g, context, now, memo)
  end

  defp target_statuses({:endorsement, id}, context, now, memo) do
    endorsement = context.endorsements[id]

    statuses =
      Map.new(context.members, fn m ->
        awards = Map.get(context.awards_by_member, m.id, [])
        {m.id, endorsement_status(endorsement, awards, now)}
      end)

    {statuses, memo}
  end

  # A group without rules: its D4H list, which never expires.
  defp list_statuses({:group, g} = target, context) do
    member_ids = context.groups[g].member_ids
    unmet = {:unmet, [none_of([target], context)]}

    Map.new(context.members, fn m ->
      {m.id, if(MapSet.member?(member_ids, m.id), do: {:met, nil}, else: unmet)}
    end)
  end

  defp all_rules(statuses) do
    case for({:unmet, reasons} <- statuses, do: reasons) do
      [] -> {:met, statuses |> Enum.map(&elem(&1, 1)) |> earliest()}
      unmet -> {:unmet, unmet |> List.flatten() |> Enum.uniq()}
    end
  end

  defp rule_status({:in, targets}, member_id, context) do
    met = for {_t, statuses} <- targets, {:met, ends} <- [statuses[member_id]], do: ends

    case {met, targets} do
      {[], [{_target, statuses}]} -> statuses[member_id]
      {[], targets} -> {:unmet, [none_of(Enum.map(targets, &elem(&1, 0)), context)]}
      {met, _targets} -> {:met, latest(met)}
    end
  end

  defp rule_status({:not_in, targets}, member_id, context) do
    case for({t, statuses} <- targets, match?({:met, _}, statuses[member_id]), do: t) do
      [] -> {:met, nil}
      held -> {:unmet, Enum.map(held, &held_reason(&1, context))}
    end
  end

  defp none_of(targets, context) do
    {:none_of, for({:group, g} <- targets, do: context.groups[g].title),
     for({:endorsement, id} <- targets, do: context.endorsements[id].name)}
  end

  defp held_reason({:group, g}, context), do: {:in, context.groups[g].title}
  defp held_reason({:endorsement, id}, context), do: {:holds, context.endorsements[id].name}

  # An In rule lasts as long as the last of its targets, and a group as its first rule.
  defp latest(ends), do: if(nil in ends, do: nil, else: Enum.max_by(ends, & &1.ends_at, DateTime))

  defp earliest(ends),
    do: ends |> Enum.reject(&is_nil/1) |> Enum.min_by(& &1.ends_at, DateTime, fn -> nil end)

  defp endorsement_status(endorsement, awards, now) do
    ids = endorsement.qualification_ids
    awards = Enum.filter(awards, &(&1.d4h_qualification_id in ids))

    if Enum.any?(awards, &MemberQualificationAward.active?(&1, now)),
      do: {:met, endorsement_ends(awards, now)},
      else: {:unmet, [unmet_reason(endorsement, awards, now)]}
  end

  # It stays met until the latest end among its awards that haven't ended, counting a
  # renewal that hasn't started yet. An award with no end never expires.
  defp endorsement_ends(awards, now) do
    covering = Enum.reject(awards, &MemberQualificationAward.expired?(&1, now))

    if Enum.any?(covering, &is_nil(&1.ends_at)),
      do: nil,
      else:
        covering
        |> Enum.max_by(& &1.ends_at, DateTime)
        |> Map.take([:d4h_qualification_id, :ends_at])
  end

  # Not met, so every award for it has either not started or ended.
  defp unmet_reason(endorsement, awards, now) do
    {upcoming, ended} = Enum.split_with(awards, &not_started?(&1, now))

    cond do
      upcoming != [] ->
        award = Enum.min_by(upcoming, & &1.starts_at, DateTime)
        {:not_started, award.d4h_qualification_id, award.starts_at}

      ended != [] ->
        award = Enum.max_by(ended, & &1.ends_at, DateTime)
        {:expired, award.d4h_qualification_id, award.ends_at}

      true ->
        {:none_of, [], [endorsement.name]}
    end
  end

  defp not_started?(%{starts_at: starts_at}, now),
    do: not is_nil(starts_at) and DateTime.after?(starts_at, now)

  @doc "A reason from `plan/3` as a sentence for the page and the change log."
  def describe({:left, left_at}, _titles, timezone),
    do: "Left the team #{Service.Format.date_short(left_at, timezone)}"

  def describe({:none_of, [], names}, _titles, _timezone),
    do: "No #{Enum.join(names, " or ")} on record"

  def describe({:none_of, groups, []}, _titles, _timezone),
    do: "Not in #{Enum.join(groups, " or ")}"

  def describe({:none_of, groups, names}, _titles, _timezone),
    do: "Not in #{Enum.join(groups, " or ")}, and no #{Enum.join(names, " or ")} on record"

  def describe({:in, title}, _titles, _timezone), do: "In #{title}"
  def describe({:holds, name}, _titles, _timezone), do: "Holds #{name}"

  def describe({:expired, qualification_id, ends_at}, titles, timezone),
    do:
      "#{title(titles, qualification_id)} expired #{Service.Format.date_short(ends_at, timezone)}"

  def describe({:not_started, qualification_id, starts_at}, titles, timezone),
    do:
      "#{title(titles, qualification_id)} starts #{Service.Format.date_short(starts_at, timezone)}"

  def describe({:expires, qualification_id, ends_at}, titles, timezone),
    do:
      "#{title(titles, qualification_id)} expires #{Service.Format.date_short(ends_at, timezone)}"

  defp title(titles, qualification_id), do: Map.get(titles, qualification_id, "Unknown")

  @doc "A problem from `problems/2` as a sentence for the group page."
  def describe_problem(:no_rules), do: "It has no rules."

  def describe_problem(:no_in_rule),
    do: "It has only Not in rules, which would add every member. Add an In rule."

  def describe_problem(:empty_rule),
    do: "A rule has no groups or endorsements. Add one or remove the rule."

  def describe_problem({:empty_endorsement, name}),
    do: "Nothing earns #{name}. Add a qualification to it."

  def describe_problem({:missing_qualification, name}),
    do: "#{name} names a qualification that is no longer in D4H. Remove or replace it."

  def describe_problem({:missing_group, d4h_group_id}),
    do:
      "A rule names a group that is no longer in D4H (#{d4h_group_id}). Remove it from the rule."

  def describe_problem({:broken_group, title}),
    do: "The rules of #{title} need fixing first."

  def describe_problem({:loop, title}),
    do: "#{title} leads back to this group. Remove one of the rules that make the loop."

  defp build_preview(plan, describe, now) do
    ids = Enum.concat([plan.add, Map.keys(plan.remove), Map.keys(plan.expiring)])
    members = load_members(ids)

    expiring =
      members
      |> rows(plan.expiring, &expiring_row(&1, describe, now))
      |> Enum.sort_by(& &1.days)

    %{
      problems: [],
      to_add:
        rows(members, Map.new(plan.add, &{&1, nil}), fn _ -> %{reason: "Meets all rules"} end),
      to_remove: rows(members, plan.remove, &%{reason: Enum.map_join(&1, " · ", describe)}),
      expiring: expiring
    }
  end

  # One row for each member in `by_member`, in name order.
  defp rows(members, by_member, build) do
    for member <- members, Map.has_key?(by_member, member.id) do
      by_member[member.id] |> build.() |> Map.put(:member, member)
    end
  end

  defp expiring_row(award, describe, now) do
    %{
      reason: describe.({:expires, award.d4h_qualification_id, award.ends_at}),
      days: DateTime.diff(award.ends_at, now, :day)
    }
  end

  defp list_awards(_team_id, []), do: []

  defp list_awards(team_id, d4h_qualification_ids) do
    MemberQualificationAward
    |> join(:inner, [a], m in assoc(a, :member))
    |> join(:inner, [a], q in assoc(a, :qualification))
    |> where([a, m, q], m.team_id == ^team_id and q.team_id == ^team_id)
    |> where([a, m, q], q.d4h_qualification_id in ^d4h_qualification_ids)
    |> select([a, m, q], %{
      member_id: a.member_id,
      d4h_qualification_id: q.d4h_qualification_id,
      starts_at: a.starts_at,
      ends_at: a.ends_at
    })
    |> Repo.all()
  end

  defp load_members([]), do: []

  defp load_members(member_ids) do
    Member
    |> where([m], m.id in ^Enum.uniq(member_ids))
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end
end
