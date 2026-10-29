defmodule App.ViewModel.EquipmentItemFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.EquipmentItem

  @types [{"Equipment", "equipment"}, {"Vehicle", "vehicle"}, {"Supply", "supply"}]

  @statuses [
    {"In service", "operational"},
    {"Unserviceable", "unserviceable"},
    {"Lost", "lost"},
    {"Retired", "retired"}
  ]

  # Adding or changing an equipment item of a team on SAR Duty Records (#271). `place`
  # is where it is, as a value from places/3: "Team", "EquipmentLocation:<id>",
  # "Equipment:<id>", "Member:<id>", or "new" for `new_place`, a location by title.
  @primary_key false
  embedded_schema do
    field :title, Field.TrimmedString
    field :item_type, :string, default: "equipment"
    field :status, :string, default: "operational"
    field :place, :string, default: "Team"
    field :new_place, Field.TrimmedString
    field :barcode, Field.TrimmedString
    field :serial, Field.TrimmedString
    field :expires_on, :date
  end

  @fields [:title, :item_type, :status, :place, :new_place, :barcode, :serial, :expires_on]

  # D4H's PATCH sets these. It retires an item only in its web app.
  @d4h_statuses ~w(operational unserviceable lost)

  def types, do: @types
  def statuses, do: @statuses

  @doc "The statuses a team in `service` sets from the form."
  def statuses(:records), do: @statuses
  def statuses(:d4h), do: Enum.filter(@statuses, &(elem(&1, 1) in @d4h_statuses))

  @doc "Whether the form changes `item`'s status, which D4H does only from these."
  def status_changes?(_item, :records), do: true
  def status_changes?(%EquipmentItem{status: status}, :d4h), do: status in @d4h_statuses

  @doc "The form for an item, in the team's time zone, or an empty one."
  def from_item(nil, _timezone), do: %__MODULE__{}

  def from_item(%EquipmentItem{} = item, timezone) do
    %__MODULE__{
      title: item.title,
      item_type: item.item_type,
      status:
        if(item.status in Enum.map(@statuses, &elem(&1, 1)), do: item.status, else: "operational"),
      place: place(item),
      barcode: item.barcode,
      serial: item.serial,
      expires_on:
        item.expires_at && item.expires_at |> Service.Convert.utc_to_local(timezone) |> elem(0)
    }
  end

  @doc "Where an item is, as a `place` value. Its member must be preloaded."
  def place(%EquipmentItem{d4h_container_id: id}) when is_integer(id), do: "Equipment:#{id}"
  def place(%EquipmentItem{member: %{d4h_member_id: id}}), do: "Member:#{id}"

  def place(%EquipmentItem{d4h_location_id: id}) when is_integer(id),
    do: "EquipmentLocation:#{id}"

  def place(%EquipmentItem{}), do: "Team"

  @doc """
  The place select's options, grouped: the team, its locations, the items `item` could
  go inside, and its members, then a new location.
  """
  def places(items, members, item) do
    groups =
      Enum.reject(
        [
          {"Places", locations(items)},
          {"Inside an item", containers(items, item)},
          {"With a member", Enum.map(members, &{&1.name, "Member:#{&1.d4h_member_id}"})}
        ],
        &(elem(&1, 1) == [])
      )

    [{"The team", "Team"} | groups] ++ [{"A new place…", "new"}]
  end

  defp locations(items) do
    items
    |> Enum.filter(& &1.d4h_location_id)
    |> Enum.uniq_by(& &1.d4h_location_id)
    |> Enum.map(&{&1.location_title || "Location #{&1.d4h_location_id}", &1.d4h_location_id})
    |> Enum.sort()
    |> Enum.map(fn {title, id} -> {title, "EquipmentLocation:#{id}"} end)
  end

  defp containers(items, item) do
    items
    |> Enum.reject(&(item && inside?(&1, item, items)))
    |> Enum.map(&{&1.title, "Equipment:#{&1.d4h_equipment_id}"})
  end

  # Whether `candidate` is `item` or sits inside it, at any depth.
  defp inside?(candidate, item, items) do
    by_id = Map.new(items, &{&1.d4h_equipment_id, &1})

    candidate
    |> Stream.iterate(&(&1 && by_id[&1.d4h_container_id]))
    |> Stream.take_while(& &1)
    |> Enum.take(50)
    |> Enum.any?(&(&1.d4h_equipment_id == item.d4h_equipment_id))
  end

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(params, @fields)
    |> validate_required([:title], message: "Enter a name.")
    |> validate_length(:title, max: 100)
    |> validate_inclusion(:item_type, Enum.map(@types, &elem(&1, 1)))
    |> validate_inclusion(:status, Enum.map(@statuses, &elem(&1, 1)))
    |> validate_length(:barcode, max: 80)
    |> validate_length(:serial, max: 100)
    |> validate_format(:place, ~r/^(Team|new|(EquipmentLocation|Equipment|Member):\d+)$/)
    |> validate_new_place()
  end

  defp validate_new_place(changeset) do
    if get_field(changeset, :place) == "new",
      do:
        changeset
        |> validate_required([:new_place], message: "Enter the new place.")
        |> validate_length(:new_place, max: 100),
      else: changeset
  end

  def validate(form, params), do: form |> changeset(params) |> apply_action(:insert)
end
