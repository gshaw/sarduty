defmodule App.Operation.RefreshD4HData.UpsertEquipmentUsages do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Operation.RefreshD4HData.UpsertEquipmentItems
  alias App.Repo

  require Logger

  def call(d4h, team, progress) do
    case UpsertEquipmentItems.no_equipment(fn -> D4H.fetch_equipment_usages(d4h) end) do
      {:ok, usages} ->
        progress = Progress.update_stage(progress, "Equipment usages", length(usages))
        context = build_context(team.id)
        Enum.each(usages, &upsert(context, &1))
        delete_stale(team.id, MapSet.new(usages, & &1.d4h_equipment_usage_id))
        {length(usages), Progress.add_page(progress, length(usages))}

      :none ->
        {0, progress}
    end
  end

  @doc "Local ids by D4H id, for the team's activities and items, and its usages."
  def build_context(team_id) do
    %{
      team_id: team_id,
      activities: ids(Activity, team_id, :d4h_activity_id),
      items: ids(EquipmentItem, team_id, :d4h_equipment_id),
      existing:
        EquipmentUsage
        |> where([u], u.team_id == ^team_id)
        |> Repo.all()
        |> Map.new(&{&1.d4h_equipment_usage_id, &1})
    }
  end

  defp ids(schema, team_id, d4h_field) do
    schema
    |> where([r], r.team_id == ^team_id)
    |> select([r], {field(r, ^d4h_field), r.id})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Saves a usage. One for an activity or item this copy doesn't have is skipped."
  def upsert(context, %D4H.EquipmentUsage{} = usage) do
    activity_id = context.activities[usage.d4h_activity_id]
    item_id = context.items[usage.d4h_equipment_id]

    if activity_id && item_id do
      params = %{
        team_id: context.team_id,
        activity_id: activity_id,
        equipment_item_id: item_id,
        d4h_equipment_usage_id: usage.d4h_equipment_usage_id,
        minutes: usage.minutes,
        distance: usage.distance,
        used: usage.used
      }

      (context.existing[usage.d4h_equipment_usage_id] || %EquipmentUsage{})
      |> EquipmentUsage.build_changeset(params)
      |> Repo.insert_or_update!()
    end
  end

  def delete_stale(team_id, synced_d4h_ids) do
    stale_ids =
      EquipmentUsage
      |> where([u], u.team_id == ^team_id)
      |> StaleRows.ids(:d4h_equipment_usage_id, synced_d4h_ids)

    {count, _} = EquipmentUsage |> where([u], u.id in ^stale_ids) |> Repo.delete_all()
    if count > 0, do: Logger.info("Deleted #{count} stale equipment usages for team #{team_id}")
  end

  @doc """
  Replaces an activity's usages with D4H's `usages`, after SAR Duty adds or removes
  equipment, so the page shows them before the next sync.
  """
  def replace_for_activity(%Activity{} = activity, usages) do
    context = build_context(activity.team_id)
    Enum.each(usages, &upsert(context, &1))
    kept = Enum.map(usages, & &1.d4h_equipment_usage_id)

    EquipmentUsage
    |> where([u], u.team_id == ^activity.team_id and u.activity_id == ^activity.id)
    |> where([u], u.d4h_equipment_usage_id not in ^kept)
    |> Repo.delete_all()
  end
end
