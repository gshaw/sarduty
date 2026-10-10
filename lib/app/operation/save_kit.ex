defmodule App.Operation.SaveKit do
  @moduledoc """
  Saves or deletes a kit (#271). A kit is SAR Duty's own, so nothing goes to D4H.

  `lines` are `%{equipment_item_id: id, minutes: n}`. A line whose item isn't the team's
  is dropped, so a kit never points at another team's equipment.
  """

  import Ecto.Query

  alias App.Model.EquipmentItem
  alias App.Model.Kit
  alias App.Model.KitItem
  alias App.Model.Team
  alias App.Repo

  @doc "`{:ok, kit}`, or `{:error, changeset}` to show on the form."
  def save(%Team{} = team, kit, params, lines) do
    kit = kit || %Kit{team_id: team.id, kit_items: []}
    kit_items = kit_items(team, lines)

    kit
    |> Kit.build_changeset(params)
    |> Ecto.Changeset.put_assoc(:kit_items, kit_items)
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
end
