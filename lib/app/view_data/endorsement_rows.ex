defmodule App.ViewData.EndorsementRows do
  alias App.Model.Endorsement
  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.BuildCardQualifications

  # The endorsements page: one row per endorsement, with what earns it, how many current
  # members hold it, and the groups whose rules name it. Each row also carries what a
  # manager should fix: `missing` counts qualifications D4H no longer has, and `same_as`
  # lists endorsements with exactly the same qualifications, counting what includes add.
  # `hidden_by` lists the on-card endorsements that stand for this one on a card that has
  # both. Nobody holding an endorsement is not a problem: endorsements will come from the
  # org, and many teams have members without some of them.

  def for_team(%Team{} = team, now) do
    team.id
    |> Endorsement.get_all()
    |> rows(
      groups_by_endorsement(team.id),
      team.id |> Qualification.get_all() |> Map.new(&{&1.d4h_qualification_id, &1.title}),
      MemberQualificationAward.get_all_active_for_team(team.id, now)
    )
  end

  @doc "Each endorsement id with the groups whose rules name it. A deleted group drops out."
  def groups_by_endorsement(team_id) do
    groups = team_id |> Group.get_all() |> Map.new(&{&1.d4h_group_id, &1})

    team_id
    |> GroupRule.get_all()
    |> Enum.flat_map(&endorsement_groups(&1, groups[&1.d4h_group_id]))
    |> Enum.uniq()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, groups} -> {id, Enum.sort_by(groups, & &1.title)} end)
  end

  defp endorsement_groups(_rule, nil), do: []

  defp endorsement_groups(rule, group),
    do: for({:endorsement, id} <- GroupRule.targets(rule), do: {id, group})

  @doc """
  Pure. `groups` is each endorsement id's groups, `titles` is keyed by D4H id, and
  `awards` are `{member_id, d4h_qualification_id}`.
  """
  def rows(endorsements, groups, titles, awards) do
    names = Map.new(endorsements, &{&1.id, &1.name})
    rows = Enum.map(endorsements, &row(&1, Map.get(groups, &1.id, []), titles, awards, names))
    on_card = for r <- rows, r.on_card, do: {r, r.ids, nil}

    Enum.map(rows, fn row ->
      row
      |> Map.put(:same_as, same_as(row, rows))
      |> Map.put(:hidden_by, hidden_by(row, on_card))
    end)
  end

  defp same_as(row, rows),
    do: for(o <- rows, o.id != row.id, o.ids == row.ids, row.ids != MapSet.new(), do: link(o))

  @doc "True when the row has something for a manager to fix."
  def problem?(row), do: row.missing > 0 or empty?(row) or row.same_as != []

  @doc "True when nothing earns the endorsement: no qualifications and no includes."
  def empty?(row), do: row.ids == MapSet.new()

  # `qualifications` and `missing` are the endorsement's own, and `includes` names the
  # endorsements it includes. `ids` and `members` count what the includes add.
  defp row(endorsement, groups, titles, awards, names) do
    ids = endorsement |> Endorsement.qualification_ids() |> MapSet.new()
    own = Endorsement.own_qualification_ids(endorsement)

    %{
      id: endorsement.id,
      name: endorsement.name,
      on_card: endorsement.on_card,
      ids: ids,
      qualifications: own |> Enum.map(&titles[&1]) |> Enum.reject(&is_nil/1) |> Enum.sort(),
      includes: include_links(endorsement, names),
      missing: Enum.count(own, &(not Map.has_key?(titles, &1))),
      members: count_members(awards, ids),
      groups: Enum.sort_by(groups, & &1.title)
    }
  end

  defp include_links(endorsement, names) do
    for id <- endorsement.included_ids || [], name = names[id] do
      %{id: id, name: name}
    end
    |> Enum.sort_by(& &1.name)
  end

  defp count_members(awards, ids),
    do:
      for({member_id, id} <- awards, MapSet.member?(ids, id), uniq: true, do: member_id)
      |> length()

  defp hidden_by(%{on_card: false}, _on_card), do: []

  defp hidden_by(row, on_card) do
    for {other, ids, _} <- on_card,
        other.id != row.id,
        BuildCardQualifications.covered?(row.ids, [{other.name, ids, nil}]),
        do: link(other)
  end

  defp link(row), do: Map.take(row, [:id, :name])
end
