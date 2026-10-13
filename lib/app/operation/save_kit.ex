defmodule App.Operation.SaveKit do
  @moduledoc """
  Saves or deletes a kit (#271). A kit is SAR Duty's own, so nothing goes to D4H.

  `lines` are `%{equipment_item_id: id, minutes: n}`, and `tag_ids` and `group_ids` local
  ids (#162). An item, tag, or group that isn't the team's is dropped, so a kit never
  points at another team's records.
  """

  import Ecto.Query

  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.Kit
  alias App.Model.KitGroup
  alias App.Model.KitItem
  alias App.Model.KitTag
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, kit}`, or `{:error, changeset}` to show on the form."
  def save(%Team{} = team, kit, params, lines, tag_ids \\ [], group_ids \\ []) do
    kit = kit || %Kit{team_id: team.id, kit_items: [], kit_tags: [], kit_groups: []}

    kit
    |> Kit.build_changeset(params)
    |> Ecto.Changeset.put_assoc(:kit_items, kit_items(team, lines))
    |> Ecto.Changeset.put_assoc(:kit_tags, kit_tags(team, tag_ids))
    |> Ecto.Changeset.put_assoc(:kit_groups, kit_groups(team, group_ids))
    |> Repo.insert_or_update()
  end

  def delete(%Team{} = team, %Kit{team_id: team_id} = kit) when team_id == team.id do
    {:ok, _kit} = Repo.delete(kit)
    :ok
  end

  defp kit_items(team, lines) do
    lines = Enum.uniq_by(lines, & &1.equipment_item_id)
    ids = Enum.map(lines, & &1.equipment_item_id)

    team_ids =
      EquipmentItem
      |> where([i], i.team_id == ^team.id and i.id in ^ids)
      |> select([i], i.id)
      |> Repo.all()
      |> MapSet.new()

    for line <- lines, MapSet.member?(team_ids, line.equipment_item_id) do
      %KitItem{equipment_item_id: line.equipment_item_id, minutes: max(line.minutes || 0, 0)}
    end
  end

  defp kit_tags(team, tag_ids) do
    tag_ids = Enum.uniq(tag_ids)

    team_ids =
      Tag
      |> where([t], t.team_id == ^team.id and t.id in ^tag_ids)
      |> select([t], t.id)
      |> Repo.all()
      |> MapSet.new()

    for id <- tag_ids, MapSet.member?(team_ids, id), do: %KitTag{tag_id: id}
  end

  defp kit_groups(team, group_ids) do
    group_ids = Enum.uniq(group_ids)

    team_ids =
      Group
      |> where([g], g.team_id == ^team.id and g.id in ^group_ids)
      |> select([g], g.id)
      |> Repo.all()
      |> MapSet.new()

    for id <- group_ids, MapSet.member?(team_ids, id), do: %KitGroup{group_id: id}
  end
end
