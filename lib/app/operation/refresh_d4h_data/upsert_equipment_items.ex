defmodule App.Operation.RefreshD4HData.UpsertEquipmentItems do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Repo

  require Logger

  # D4H answers these for a team without its equipment module, and SAR Duty Records has
  # no equipment. Either way the team has none to copy, which isn't a failed refresh.
  @no_equipment [403, 404]

  def call(d4h, team, progress) do
    case fetch(d4h) do
      {:ok, items} ->
        progress = Progress.update_stage(progress, "Equipment", length(items))
        members = member_ids(team.id)
        existing = existing(team.id)
        Enum.each(items, &upsert(team.id, &1, members, existing))
        delete_stale(team.id, MapSet.new(items, & &1.d4h_equipment_id))
        {length(items), Progress.add_page(progress, length(items))}

      :none ->
        {0, progress}
    end
  end

  @doc "Runs `fetch`, or `:none` when the team has no equipment in D4H."
  def no_equipment(fetch) do
    {:ok, fetch.()}
  rescue
    error in D4H.Error ->
      if error.status in @no_equipment, do: :none, else: reraise(error, __STACKTRACE__)
  end

  defp fetch(d4h), do: no_equipment(fn -> D4H.fetch_equipment_items(d4h) end)

  # An item D4H deleted takes its usages and its place in kits with it.
  def delete_stale(team_id, synced_d4h_ids) do
    stale_ids =
      EquipmentItem
      |> where([i], i.team_id == ^team_id)
      |> StaleRows.ids(:d4h_equipment_id, synced_d4h_ids)

    {count, _} = EquipmentItem |> where([i], i.id in ^stale_ids) |> Repo.delete_all()
    if count > 0, do: Logger.info("Deleted #{count} stale equipment items for team #{team_id}")
  end

  defp upsert(team_id, item, members, existing) do
    params =
      item
      |> Map.from_struct()
      |> Map.take(EquipmentItem.fields())
      |> Map.merge(%{
        team_id: team_id,
        member_id: item.d4h_member_id && members[item.d4h_member_id]
      })

    case existing[item.d4h_equipment_id] do
      nil -> %EquipmentItem{} |> EquipmentItem.build_changeset(params) |> Repo.insert!()
      record -> record |> EquipmentItem.build_changeset(params) |> Repo.update!()
    end
  end

  defp existing(team_id) do
    EquipmentItem
    |> where([i], i.team_id == ^team_id)
    |> Repo.all()
    |> Map.new(&{&1.d4h_equipment_id, &1})
  end

  defp member_ids(team_id) do
    Member
    |> where([m], m.team_id == ^team_id)
    |> select([m], {m.d4h_member_id, m.id})
    |> Repo.all()
    |> Map.new()
  end
end
