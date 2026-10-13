defmodule App.ViewData.CardNames do
  alias App.Model.Group
  alias App.Model.GroupRuleClause
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team

  # The ID cards settings page: one row per clause name. Clauses that share a name count
  # as one on cards (BuildCardQualifications.summarize/3), so a row shows every
  # qualification under the name, how many current members hold one, and the groups whose
  # rules set it. `missing` counts qualifications D4H no longer has.

  def for_team(%Team{} = team, now) do
    team.id
    |> GroupRuleClause.get_all_named()
    |> rows(
      team.id |> Group.get_all() |> Map.new(&{&1.d4h_group_id, &1}),
      team.id |> Qualification.get_all() |> Map.new(&{&1.d4h_qualification_id, &1.title}),
      MemberQualificationAward.get_all_active_for_team(team.id, now)
    )
  end

  @doc "Pure. `groups` and `titles` are keyed by D4H id; `awards` is `{member_id, d4h_id}`."
  def rows(clauses, groups, titles, awards) do
    clauses
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {name, same_name} -> row(name, same_name, groups, titles, awards) end)
    |> Enum.sort_by(& &1.name)
    |> Enum.with_index(fn row, i -> Map.put(row, :index, i) end)
  end

  defp row(name, clauses, groups, titles, awards) do
    ids = qualification_ids(clauses)

    %{
      name: name,
      on_card: Enum.any?(clauses, & &1.on_card),
      qualifications: ids |> Enum.map(&titles[&1]) |> Enum.reject(&is_nil/1) |> Enum.sort(),
      missing: Enum.count(ids, &(not Map.has_key?(titles, &1))),
      members: count_members(awards, ids),
      groups: groups_of(clauses, groups)
    }
  end

  defp qualification_ids(clauses) do
    for clause <- clauses,
        cq <- clause.group_rule_clause_qualifications,
        into: MapSet.new(),
        do: cq.d4h_qualification_id
  end

  defp count_members(awards, ids),
    do:
      for({member_id, id} <- awards, MapSet.member?(ids, id), uniq: true, do: member_id)
      |> length()

  defp groups_of(clauses, groups) do
    clauses
    |> Enum.map(&groups[&1.d4h_group_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.title)
  end
end
