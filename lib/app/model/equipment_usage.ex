defmodule App.Model.EquipmentUsage do
  use App, :model

  alias App.Model.Activity
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Team
  alias App.Repo

  # A copy of one D4H equipment usage: an item that went on an activity (#271). D4H
  # takes minutes for equipment, km for a vehicle, and a count for a supply.
  schema "equipment_usages" do
    belongs_to :team, Team
    belongs_to :activity, Activity
    belongs_to :equipment_item, EquipmentItem
    field :d4h_equipment_usage_id, :integer
    field :minutes, :integer
    field :distance, :integer
    field :used, :integer
    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :team_id,
    :activity_id,
    :equipment_item_id,
    :d4h_equipment_usage_id,
    :minutes,
    :distance,
    :used
  ]

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, @fields)
    |> validate_required([:team_id, :activity_id, :equipment_item_id, :d4h_equipment_usage_id])
  end

  @doc "An activity's usages with their items, by item title."
  def for_activity(%Activity{} = activity) do
    EquipmentUsage
    |> where([u], u.team_id == ^activity.team_id and u.activity_id == ^activity.id)
    |> join(:inner, [u], i in assoc(u, :equipment_item))
    |> order_by([u, i], asc: i.title, asc: u.id)
    |> preload([u, i], equipment_item: i)
    |> Repo.all()
  end

  @doc "An item's usages with their activities, newest first."
  def for_item(%EquipmentItem{} = item) do
    EquipmentUsage
    |> where([u], u.team_id == ^item.team_id and u.equipment_item_id == ^item.id)
    |> join(:inner, [u], a in assoc(u, :activity))
    |> where([u, a], is_nil(a.deleted_at))
    |> order_by([u, a], desc: a.started_at, desc: u.id)
    |> preload([u, a], activity: a)
    |> Repo.all()
  end

  @doc """
  The newest activity of `kind` before `activity` that has equipment, or nil. "Same as
  last incident" copies its items.
  """
  def last_activity_with_equipment(%Activity{} = activity) do
    used = from(u in EquipmentUsage, where: u.activity_id == parent_as(:activity).id)

    query =
      from(a in Activity,
        as: :activity,
        where: a.team_id == ^activity.team_id and a.activity_kind == ^activity.activity_kind,
        where: a.id != ^activity.id and is_nil(a.deleted_at),
        where: a.started_at <= ^activity.started_at and exists(used),
        order_by: [desc: a.started_at, desc: a.id],
        limit: 1
      )

    Repo.one(query)
  end
end
