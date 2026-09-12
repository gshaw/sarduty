defmodule App.Operation.BuildGroupRulePreview do
  import Ecto.Query

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRuleClause
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  # Matches D4H's default reminder before a qualification expires.
  @expiring_days 60

  def expiring_days, do: @expiring_days

  # Group rules are CNF: a member qualifies when every clause lists at least one
  # qualification they hold with an active award. `current_members` are the group's
  # members now, each with `id` and `left_at`.
  def call(clauses, current_members, %Team{} = team, now \\ DateTime.utc_now()) do
    clause_qualification_ids = clause_qualification_ids(clauses)

    titles =
      team.id
      |> Qualification.get_all()
      |> Map.new(&{&1.d4h_qualification_id, &1.title})

    case missing_qualification_ids(clause_qualification_ids, Map.keys(titles)) do
      [] ->
        awards = list_awards(team.id, List.flatten(clause_qualification_ids))
        plan = plan(clause_qualification_ids, awards, current_members, now)
        describe = &describe(&1, titles, team.timezone)
        build_preview(plan, describe, now)

      missing ->
        %{missing_qualification_ids: missing, to_add: [], to_remove: [], expiring: []}
    end
  end

  def for_group(%Team{} = team, %Group{} = group, now \\ DateTime.utc_now()) do
    clauses = GroupRuleClause.get_all_for_group(team.id, group.d4h_group_id)

    current_members =
      Member
      |> join(:inner, [m], gm in GroupMember, on: gm.member_id == m.id)
      |> where([m, gm], gm.group_id == ^group.id and m.team_id == ^team.id)
      |> Repo.all()

    call(clauses, current_members, team, now)
  end

  def clause_qualification_ids(clauses) do
    Enum.map(clauses, fn clause ->
      Enum.map(clause.group_rule_clause_qualifications, & &1.d4h_qualification_id)
    end)
  end

  # A qualification deleted in D4H, or deleted and recreated with a new id, has no
  # local row. A clause naming only that would match nobody and remove everyone, so
  # the caller must plan nothing until the rule is fixed.
  def missing_qualification_ids(clause_qualification_ids, known_qualification_ids) do
    known = MapSet.new(known_qualification_ids)

    clause_qualification_ids
    |> List.flatten()
    |> Enum.reject(&MapSet.member?(known, &1))
    |> Enum.uniq()
  end

  @doc """
  Returns the member ids to add, the members to remove with why, and the members who
  qualify now but won't within #{@expiring_days} days, with the award that runs out.

  A clause with no qualifications would disqualify everyone, so an incomplete rule set
  plans no changes rather than emptying the group.
  """
  def plan(clause_qualification_ids, awards, current_members, now) do
    if clause_qualification_ids == [] || Enum.any?(clause_qualification_ids, &(&1 == [])) do
      %{add: MapSet.new(), remove: %{}, expiring: %{}}
    else
      awards_by_member = Enum.group_by(awards, & &1.member_id)
      qualifying = qualifying_member_ids(clause_qualification_ids, awards_by_member, now)
      current = MapSet.new(current_members, & &1.id)

      remove =
        current_members
        |> Enum.reject(&MapSet.member?(qualifying, &1.id))
        |> Map.new(fn member ->
          member_awards = Map.get(awards_by_member, member.id, [])
          {member.id, reasons(member, clause_qualification_ids, member_awards, now)}
        end)

      %{
        add: MapSet.difference(qualifying, current),
        remove: remove,
        expiring: expiring(qualifying, clause_qualification_ids, awards_by_member, now)
      }
    end
  end

  defp qualifying_member_ids(clause_qualification_ids, awards_by_member, now) do
    awards_by_member
    |> Enum.filter(fn {_member_id, [award | _] = member_awards} ->
      Member.current?(%{left_at: award.member_left_at}, now) and
        Enum.all?(clause_qualification_ids, &clause_met?(&1, member_awards, now))
    end)
    |> MapSet.new(fn {member_id, _awards} -> member_id end)
  end

  defp clause_met?(clause, member_awards, now) do
    Enum.any?(member_awards, fn award ->
      award.d4h_qualification_id in clause and MemberQualificationAward.active?(award, now)
    end)
  end

  defp reasons(member, clause_qualification_ids, member_awards, now) do
    if Member.current?(member, now) do
      clause_qualification_ids
      |> Enum.reject(&clause_met?(&1, member_awards, now))
      |> Enum.map(&clause_reason(&1, member_awards, now))
    else
      [{:left, member.left_at}]
    end
  end

  # The clause isn't met, so every award for it has either not started or ended.
  defp clause_reason(clause, member_awards, now) do
    clause_awards = Enum.filter(member_awards, &(&1.d4h_qualification_id in clause))

    {upcoming, ended} = Enum.split_with(clause_awards, &not_started?(&1, now))

    cond do
      upcoming != [] ->
        award = Enum.min_by(upcoming, & &1.starts_at, DateTime)
        {:not_started, award.d4h_qualification_id, award.starts_at}

      ended != [] ->
        award = Enum.max_by(ended, & &1.ends_at, DateTime)
        {:expired, award.d4h_qualification_id, award.ends_at}

      true ->
        {:missing, clause}
    end
  end

  defp not_started?(%{starts_at: starts_at}, now),
    do: not is_nil(starts_at) and DateTime.after?(starts_at, now)

  # A clause stays met until the latest end among its awards that haven't ended,
  # counting a renewal that hasn't started yet. An award with no end never expires.
  defp expiring(qualifying, clause_qualification_ids, awards_by_member, now) do
    cutoff = DateTime.add(now, @expiring_days, :day)

    qualifying
    |> Enum.map(fn member_id ->
      member_awards = Map.fetch!(awards_by_member, member_id)
      {member_id, earliest_clause_end(clause_qualification_ids, member_awards, now)}
    end)
    |> Enum.filter(fn {_member_id, award} -> award && DateTime.before?(award.ends_at, cutoff) end)
    |> Map.new(fn {member_id, award} ->
      {member_id, Map.take(award, [:d4h_qualification_id, :ends_at])}
    end)
  end

  defp earliest_clause_end(clause_qualification_ids, member_awards, now) do
    clause_qualification_ids
    |> Enum.map(fn clause ->
      covering =
        Enum.filter(member_awards, fn award ->
          award.d4h_qualification_id in clause and
            not MemberQualificationAward.expired?(award, now)
        end)

      if Enum.any?(covering, &is_nil(&1.ends_at)),
        do: nil,
        else: Enum.max_by(covering, & &1.ends_at, DateTime)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(& &1.ends_at, DateTime, fn -> nil end)
  end

  @doc "A reason from `plan/4` as a sentence for the page and the change log."
  def describe({:left, left_at}, _titles, timezone),
    do: "Left the team #{Service.Format.date_short(left_at, timezone)}"

  def describe({:missing, clause}, titles, _timezone),
    do: "No #{Enum.map_join(clause, " or ", &title(titles, &1))} on record"

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

  defp build_preview(plan, describe, now) do
    ids = Enum.concat([plan.add, Map.keys(plan.remove), Map.keys(plan.expiring)])
    members = load_members(ids)

    expiring =
      members
      |> rows(plan.expiring, &expiring_row(&1, describe, now))
      |> Enum.sort_by(& &1.days)

    %{
      missing_qualification_ids: [],
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
      member_left_at: m.left_at,
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
