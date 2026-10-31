defmodule App.ViewData.ReportRecords do
  @moduledoc """
  The records a report's rows name (#768), so its cells are the standard columns: a
  member's name and standing, an activity's title and kind, an item's status. A report's
  rows hold only ids; this loads them, through the team.
  """

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.Member
  alias App.Model.Qualification
  alias App.Model.Standing
  alias App.Model.Team
  alias App.Repo
  alias App.Report.Result

  @schemas %{
    member: Member,
    activity: Activity,
    item: EquipmentItem,
    qualification: Qualification,
    group: Group
  }

  @doc """
  `%{kind => %{id => record}}` for every record the result names, and `:standings`, each
  member's standing by id.
  """
  def load(%Result{} = result, %Team{} = team, now) do
    records =
      result
      |> ids()
      |> Map.new(fn {kind, ids} -> {kind, by_id(Map.fetch!(@schemas, kind), team, ids)} end)

    members = records |> Map.get(:member, %{}) |> Map.values()
    Map.put(records, :standings, Standing.by_member(team, members, now))
  end

  defp ids(result) do
    result.columns
    |> Enum.with_index()
    |> Enum.flat_map(&column_ids(&1, result.rows))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {kind, ids} -> {kind, ids |> Enum.reject(&is_nil/1) |> Enum.uniq()} end)
  end

  # A record's cells, or a pivot column named for a record.
  defp column_ids({%{type: {:record, kind}}, i}, rows),
    do: Enum.map(rows, &{kind, Enum.at(&1, i)})

  defp column_ids({%{pivot_type: {:record, kind}, pivot: id}, _i}, _rows) when is_integer(id),
    do: [{kind, id}]

  defp column_ids(_column, _rows), do: []

  defp by_id(_schema, _team, []), do: %{}

  defp by_id(schema, team, ids) do
    schema
    |> where([r], r.team_id == ^team.id and r.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end
end
