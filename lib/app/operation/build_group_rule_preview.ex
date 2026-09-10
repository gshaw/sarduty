defmodule App.Operation.BuildGroupRulePreview do
  import Ecto.Query

  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Repo

  # Group rules are CNF: a member qualifies when every clause lists at least one
  # qualification they hold and that has not expired.
  def call(clauses, current_member_ids, team_id, now \\ DateTime.utc_now()) do
    clause_qualification_ids =
      Enum.map(clauses, fn clause ->
        Enum.map(clause.group_rule_clause_qualifications, & &1.d4h_qualification_id)
      end)

    awards = list_awards(team_id, List.flatten(clause_qualification_ids))
    %{add: add, remove: remove} = plan(clause_qualification_ids, awards, current_member_ids, now)

    %{to_add: load_members(add), to_remove: load_members(remove)}
  end

  # A clause with no qualifications would disqualify everyone, so an incomplete
  # rule set plans no changes rather than emptying the group.
  def plan(clause_qualification_ids, awards, current_member_ids, now) do
    if clause_qualification_ids == [] || Enum.any?(clause_qualification_ids, &(&1 == [])) do
      %{add: MapSet.new(), remove: MapSet.new()}
    else
      qualifying = qualifying_member_ids(clause_qualification_ids, awards, now)
      current = MapSet.new(current_member_ids)

      %{
        add: MapSet.difference(qualifying, current),
        remove: MapSet.difference(current, qualifying)
      }
    end
  end

  defp qualifying_member_ids(clause_qualification_ids, awards, now) do
    awards
    |> Enum.filter(&(is_nil(&1.ends_at) || DateTime.after?(&1.ends_at, now)))
    |> Enum.group_by(& &1.member_id, & &1.d4h_qualification_id)
    |> Enum.filter(fn {_member_id, held} ->
      Enum.all?(clause_qualification_ids, fn clause -> Enum.any?(clause, &(&1 in held)) end)
    end)
    |> MapSet.new(fn {member_id, _held} -> member_id end)
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
      ends_at: a.ends_at
    })
    |> Repo.all()
  end

  defp load_members(member_ids) do
    if Enum.empty?(member_ids) do
      []
    else
      ids = MapSet.to_list(member_ids)

      Member
      |> where([m], m.id in ^ids)
      |> order_by([m], asc: m.name)
      |> Repo.all()
    end
  end
end
