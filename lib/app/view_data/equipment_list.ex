defmodule App.ViewData.EquipmentList do
  @moduledoc """
  The equipment page's rows (#271), grouped by where things are. D4H nests items: a
  drawer sits in a truck, which sits in the yard. Each row's `place` is where its
  outermost item is (a D4H location, "With members", or "No location"), and `inside` is
  the chain of items holding it, such as "SOUTH FRASER 2 › 02 DRAWER #1".

  A member is a place too, as in D4H (#490): the Place filter takes `"member-<id>"`, the
  member's local id, and keeps the rows `EquipmentItem.held_by/2` finds. The browse
  page's Place table keeps one "With members" row.

  Pure: items in, rows out. Items need their `member` preloaded.
  """

  alias App.Model.EquipmentItem

  @with_members "With members"
  @no_location "No location"
  @no_category "No category"

  @max_depth EquipmentItem.max_depth()

  # The page's stat switch. Who holds an item is the Place filter's "With members".
  def shows,
    do: [
      {"All", "all"},
      {"In service", "in-service"},
      {"Expiring in 60 days", "expiring"},
      {"Unserviceable or lost", "problems"},
      {"Retired", "retired"}
    ]

  def show_values, do: Enum.map(shows(), &elem(&1, 1))

  @doc "A row per item: `%{item, place, inside, holder, holder_id, path}`."
  def rows(items) do
    by_d4h_id = Map.new(items, &{&1.d4h_equipment_id, &1})
    Enum.map(items, &row(&1, by_d4h_id))
  end

  defp row(item, by_d4h_id) do
    chain = containers(item, by_d4h_id, [], 0)
    outermost = List.first(chain) || item

    %{
      item: item,
      place: place(outermost),
      inside: Enum.map_join(chain, " › ", & &1.title),
      holder: outermost.member && outermost.member.name,
      holder_id: outermost.member_id,
      path: path(item, chain)
    }
  end

  # The items holding `item`, outermost first.
  defp containers(_item, _by_d4h_id, chain, @max_depth), do: chain

  defp containers(%EquipmentItem{d4h_container_id: nil}, _by_d4h_id, chain, _depth), do: chain

  defp containers(item, by_d4h_id, chain, depth) do
    case by_d4h_id[item.d4h_container_id] do
      nil -> chain
      container -> containers(container, by_d4h_id, [container | chain], depth + 1)
    end
  end

  defp place(%EquipmentItem{member_id: id}) when is_integer(id), do: @with_members
  defp place(%EquipmentItem{location_title: title}) when is_binary(title), do: title
  defp place(%EquipmentItem{}), do: @no_location

  @doc "The rows `show` and the search text `q` keep. `now` decides what expires soon."
  def filter(rows, show, q, now) do
    Enum.filter(rows, &(shown?(&1, show, now) and matches?(&1.item, q)))
  end

  defp shown?(%{item: item}, "in-service", _now), do: item.status != "retired"
  defp shown?(%{item: item}, "retired", _now), do: item.status == "retired"
  defp shown?(%{item: item}, "problems", _now), do: item.status in ["unserviceable", "lost"]

  defp shown?(%{item: item}, "expiring", now), do: expiring?(item, now)
  defp shown?(_row, _all, _now), do: true

  @doc "Whether the item has expired or expires within 60 days of `now`."
  def expiring?(%EquipmentItem{expires_at: nil}, _now), do: false

  def expiring?(%EquipmentItem{status: "retired"}, _now), do: false

  def expiring?(%EquipmentItem{expires_at: expires_at}, now),
    do: Service.Convert.days_until(expires_at, now) <= 60

  defp matches?(_item, q) when q in [nil, ""], do: true

  defp matches?(item, q) do
    q = String.downcase(q)
    Enum.any?([item.title, item.barcode, item.serial, item.kind], &contains?(&1, q))
  end

  @doc """
  The rows in `place` with `category`. An empty one keeps every row. A member place
  keeps the rows whose item ids are in `held`, from `EquipmentItem.held_by/2`, so
  another team's member, or one who holds nothing, keeps none, like an unknown place.
  """
  def narrow(rows, place, category, held \\ MapSet.new()) do
    in_place? = in_place_fn(place, held)
    Enum.filter(rows, &(in_place?.(&1) and (category == "" or category(&1.item) == category)))
  end

  defp in_place_fn("", _held), do: fn _row -> true end

  defp in_place_fn(place, held) do
    case member_id(place) do
      nil -> &(&1.place == place)
      _id -> &MapSet.member?(held, &1.item.id)
    end
  end

  @doc "The member's id in a member place, `\"member-12\"`, or nil for any other place."
  def member_id("member-" <> id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _other -> nil
    end
  end

  def member_id(_place), do: nil

  @doc "A member's place, for the Place filter: `\"member-12\"`."
  def member_place(member_id), do: "member-#{member_id}"

  @doc """
  The Place filter's choices, as `{label, value}`: the places in `rows`, in group order,
  then each member who holds something, by name.
  """
  def place_options(rows) do
    rows |> places() |> Enum.map(&{elem(&1, 0), elem(&1, 0)}) |> Enum.concat(holders(rows))
  end

  defp holders(rows) do
    rows
    |> Enum.filter(& &1.holder_id)
    |> Enum.uniq_by(& &1.holder_id)
    |> Enum.sort_by(&{&1.holder, &1.holder_id})
    |> Enum.map(&{&1.holder, member_place(&1.holder_id)})
  end

  @doc """
  Whether the page lists items, or only the places and categories to pick from. South
  Fraser's 1,136 items in one list were too many to read (Andrew, 2026-10-11).
  """
  def browsing?(show, q, place, category),
    do: show == "in-service" and q == "" and place == "" and category == ""

  @doc "The places in `rows`, in group order, as `{place, count}`."
  def places(rows) do
    rows
    |> Enum.frequencies_by(& &1.place)
    |> Enum.sort_by(fn {place, _count} -> {place_order(place), place} end)
  end

  @doc "The categories in `rows` by name, then \"No category\", as `{category, count}`."
  def categories(rows) do
    rows
    |> Enum.frequencies_by(&category(&1.item))
    |> Enum.sort_by(fn {category, _count} -> {category == @no_category, category} end)
  end

  @doc "An item's category: D4H's kind, or \"No category\"."
  def category(%EquipmentItem{kind: kind}) when kind in [nil, ""], do: @no_category
  def category(%EquipmentItem{kind: kind}), do: kind

  defp contains?(nil, _q), do: false
  defp contains?(text, q), do: text |> String.downcase() |> String.contains?(q)

  @doc """
  Rows grouped by place, as `{place, rows}`: D4H locations by name, then "With
  members", then "No location". In a place, each item's contents follow it.
  """
  def group(rows) do
    rows
    |> Enum.group_by(& &1.place)
    |> sort_groups()
  end

  @doc "A member place's rows as one group named after the member, or none."
  def group_held([], _name), do: []
  def group_held(rows, name), do: sort_groups([{name, rows}])

  @doc """
  The items a member holds, from `EquipmentItem.held_by/2`, as `%{item, inside}` with
  each kit's contents right after it. `inside` is the chain of items holding it, as
  `rows/1` gives it, such as "First aid kit 6 › Splint pouch", or "" for one D4H locates
  with the member.
  """
  def held_rows(items) do
    by_d4h_id = Map.new(items, &{&1.d4h_equipment_id, &1})

    items
    |> Enum.map(&held_row(&1, containers(&1, by_d4h_id, [], 0)))
    |> Enum.sort_by(&{&1.path, &1.item.id})
    |> Enum.map(&Map.delete(&1, :path))
  end

  # `chain` is the items holding `item`, outermost first.
  defp held_row(item, chain),
    do: %{
      item: item,
      inside: Enum.map_join(chain, " › ", & &1.title),
      path: path(item, chain)
    }

  # Sorting by this puts each item's contents right after it: the items from the
  # outermost in, ending with `item`. The id keeps two kits with one title apart.
  defp path(item, chain) do
    [item | Enum.reverse(chain)]
    |> Enum.reverse()
    |> Enum.map(&{String.downcase(&1.title), &1.id})
  end

  defp sort_groups(groups) do
    groups
    |> Enum.sort_by(fn {place, _rows} -> {place_order(place), place} end)
    |> Enum.map(fn {place, rows} ->
      {place, Enum.sort_by(rows, &{&1.holder || "", &1.path, &1.item.id})}
    end)
  end

  defp place_order(@with_members), do: 1
  defp place_order(@no_location), do: 2
  defp place_order(_location), do: 0
end
