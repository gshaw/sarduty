defmodule App.Model.EquipmentItem do
  use App, :model

  alias App.Field.TrimmedString
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # A copy of one D4H equipment item (#271). An item sits in one place: a D4H location
  # (the yard), inside another item (a truck's drawer), or with a member. D4H calls the
  # item's name its `ref`. `item_type` is D4H's type, lowercased: equipment, vehicle, or
  # supply. `kind` is D4H's kind title, such as "Rescue Truck".
  schema "equipment_items" do
    belongs_to :team, Team
    belongs_to :member, Member
    field :d4h_equipment_id, :integer
    field :title, TrimmedString
    field :item_type, :string
    field :kind, :string
    field :status, :string
    field :barcode, :string
    field :serial, :string
    field :d4h_location_id, :integer
    field :location_title, :string
    field :d4h_container_id, :integer
    field :expires_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :team_id,
    :member_id,
    :d4h_equipment_id,
    :title,
    :item_type,
    :kind,
    :status,
    :barcode,
    :serial,
    :d4h_location_id,
    :location_title,
    :d4h_container_id,
    :expires_at
  ]

  def fields, do: @fields

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, @fields)
    |> validate_required([:team_id, :d4h_equipment_id, :title, :item_type, :status])
  end

  def find!(%Team{} = team, id), do: Repo.get_by!(EquipmentItem, id: id, team_id: team.id)

  @doc "Every item of the team, by title. Retired items too: their history still counts."
  def get_all(team_id) do
    EquipmentItem
    |> where([i], i.team_id == ^team_id)
    |> order_by([i], asc: i.title, asc: i.id)
    |> preload(:member)
    |> Repo.all()
  end

  @doc "Items a person can add to an activity or a kit: any but retired and lost ones."
  def in_service?(%EquipmentItem{status: status}), do: status not in ["retired", "lost"]

  @doc "Whether D4H takes hours for a usage of the item. Vehicles take km, supplies a count."
  def takes_hours?(%EquipmentItem{item_type: "equipment"}), do: true
  def takes_hours?(%EquipmentItem{}), do: false

  @doc """
  Up to `limit` in-service items whose title, barcode, or serial contains `text`, by
  title. Blank text finds nothing.
  """
  def search(team_id, text, limit \\ 20) do
    case String.trim(text || "") do
      "" ->
        []

      text ->
        # SQLite's LIKE ignores case. A % or _ typed in only widens the search.
        pattern = "%#{text}%"

        EquipmentItem
        |> where([i], i.team_id == ^team_id and i.status not in ["retired", "lost"])
        |> where(
          [i],
          like(i.title, ^pattern) or like(i.barcode, ^pattern) or like(i.serial, ^pattern)
        )
        |> order_by([i], asc: i.title, asc: i.id)
        |> limit(^limit)
        |> Repo.all()
    end
  end
end
