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

  # As deep as App.ViewData.EquipmentList follows a chain of items. It stops a loop if
  # D4H ever puts two items in each other.
  @max_depth 10

  @doc """
  The items a member holds, by title (#490): those D4H locates with the member, and
  whatever sits inside them, down to 10 levels. Retired items too: D4H still has them
  with the member, and the team may want them back. One recursive query,
  scoped by the team at every step. The member page, Your membership, and Equipment's
  member place all read this, so they always agree.
  """
  def held_by(%Team{} = team, %Member{} = member) do
    EquipmentItem
    |> where([i], i.team_id == ^team.id and i.member_id == ^member.id)
    |> held(team)
    |> distinct(true)
    |> order_by([i], asc: i.title, asc: i.id)
    |> Repo.all()
  end

  @doc """
  Every item with a retired member, as `{item, member}`, by name then title: what
  `held_by/2` finds for each of them, by the same rule, retired items too (#490). Retired is anyone not current by `Member.current_dynamic/2`.
  Equipment's With retired members and the team home's count both read this.
  """
  def held_by_retired_members(%Team{} = team, now) do
    team
    |> located_with_retired(now)
    |> held(team)
    |> with_holder(team)
    |> Repo.all()
    # An item D4H locates with a member and inside another's kit, if one ever is, once.
    |> Enum.uniq_by(fn {item, _member} -> item.id end)
  end

  # Each held item with the member it's held by, by name then title.
  defp with_holder(held, team) do
    held
    |> join(:inner, [i, h], m in Member, on: m.id == h.member_id and m.team_id == ^team.id)
    |> order_by([i, _h, m], asc: m.name, asc: m.id, asc: i.title, asc: i.id)
    |> select([i, _h, m], {i, m})
  end

  # The team's items D4H locates with a member of the team who isn't current.
  defp located_with_retired(team, now) do
    EquipmentItem
    |> join(:inner, [i], m in Member, on: m.id == i.member_id, as: :member)
    |> where([i, member: m], i.team_id == ^team.id and m.team_id == ^team.id)
    |> where(^dynamic(not (^Member.current_dynamic(now, :member))))
  end

  # cspell:ignore ctes -- Ecto's recursive_ctes/2, for SQLite's WITH RECURSIVE.
  # The team's items reached from `roots`, items D4H locates with a member: the roots and
  # whatever sits inside them, joined to the `held` rows, which carry the root's member_id.
  defp held(roots, team) do
    roots =
      select(roots, [i], %{
        id: i.id,
        d4h_equipment_id: i.d4h_equipment_id,
        member_id: i.member_id,
        depth: fragment("0")
      })

    EquipmentItem
    |> recursive_ctes(true)
    |> with_cte("held", as: ^union(roots, ^held_inside(team)))
    |> join(:inner, [i], h in "held", on: h.id == i.id)
    |> where([i], i.team_id == ^team.id)
  end

  # The team's items inside one already found, one level deeper, with its member.
  defp held_inside(team) do
    from i in EquipmentItem,
      join: h in "held",
      on: i.d4h_container_id == h.d4h_equipment_id,
      where: i.team_id == ^team.id and h.depth < @max_depth,
      select: %{
        id: i.id,
        d4h_equipment_id: i.d4h_equipment_id,
        member_id: h.member_id,
        depth: h.depth + 1
      }
  end

  @doc "Items a person can add to an activity or a template: any but retired and lost ones."
  def in_service?(%EquipmentItem{status: status}), do: status not in ["retired", "lost"]

  @doc "Whether D4H takes hours for a usage of the item. Vehicles take km, supplies a count."
  def takes_hours?(%EquipmentItem{item_type: "equipment"}), do: true
  def takes_hours?(%EquipmentItem{}), do: false

  @doc "Whether D4H takes km for a usage of the item: only vehicles."
  def takes_km?(%EquipmentItem{item_type: "vehicle"}), do: true
  def takes_km?(%EquipmentItem{}), do: false

  @doc """
  The item a scanned barcode names, ignoring case and spaces at the ends, or nil. A
  barcode match comes before a serial one. Retired and lost items count too, so a page
  can say why one cannot be added.
  """
  def find_by_code(team_id, code) do
    case String.trim(code || "") do
      "" ->
        nil

      code ->
        codes = code |> String.downcase() |> code_forms()

        EquipmentItem
        |> where([i], i.team_id == ^team_id)
        |> where(
          [i],
          fragment("lower(trim(?))", i.barcode) in ^codes or
            fragment("lower(trim(?))", i.serial) in ^codes
        )
        |> order_by([i],
          desc: fragment("lower(trim(?))", i.barcode) in ^codes,
          asc: i.status in ["retired", "lost"],
          asc: i.id
        )
        |> limit(1)
        |> Repo.one()
    end
  end

  # The reader gives a UPC-A as its 13-digit EAN, with a 0 in front, so a 12-digit
  # barcode typed from the label still matches.
  defp code_forms("0" <> upc = code) when byte_size(upc) == 12,
    do: if(String.match?(code, ~r/^\d+$/), do: [code, upc], else: [code])

  defp code_forms(code), do: [code]

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
