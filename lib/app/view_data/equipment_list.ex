defmodule App.ViewData.EquipmentList do
  @moduledoc """
  The equipment page's rows (#271), grouped by where things are. D4H nests items: a
  drawer sits in a truck, which sits in the yard. Each row's `place` is where its
  outermost item is (a D4H location, "With members", or "No location"), and `inside` is
  the chain of items holding it, such as "SOUTH FRASER 2 › 02 DRAWER #1".

  Pure: items in, rows out. Items need their `member` preloaded.
  """

  alias App.Model.EquipmentItem

  @with_members "With members"
  @no_location "No location"

  # Deeper than any real nesting. It stops a loop if D4H ever puts two items in each other.
  @max_depth 10

  def shows,
    do: [
      {"In service", "in-service"},
      {"With members", "with-members"},
      {"Expiring in 60 days", "expiring"},
      {"Unserviceable or lost", "problems"},
      {"Retired", "retired"},
      {"All", "all"}
    ]

  def show_values, do: Enum.map(shows(), &elem(&1, 1))

  @doc "A row per item: `%{item, place, inside, holder, path}`."
  def rows(items) do
    by_d4h_id = Map.new(items, &{&1.d4h_equipment_id, &1})
    Enum.map(items, &row(&1, by_d4h_id))
  end

  defp row(item, by_d4h_id) do
    chain = containers(item, by_d4h_id, [], 0)
    outermost = List.first(chain) || item
    innermost_first = [item | Enum.reverse(chain)]

    %{
      item: item,
      place: place(outermost),
      inside: Enum.map_join(chain, " › ", & &1.title),
      holder: outermost.member && outermost.member.name,
      # Sorting by this puts each item's contents right after it.
      path: innermost_first |> Enum.reverse() |> Enum.map(&String.downcase(&1.title))
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

  defp shown?(%{place: place, item: item}, "with-members", _now),
    do: place == @with_members and item.status != "retired"

  defp shown?(%{item: item}, "expiring", now), do: expiring?(item, now)
  defp shown?(_row, _all, _now), do: true

  @doc "Whether the item has expired or expires within 60 days of `now`."
  def expiring?(%EquipmentItem{expires_at: nil}, _now), do: false

  def expiring?(%EquipmentItem{status: "retired"}, _now), do: false

  def expiring?(%EquipmentItem{expires_at: expires_at}, now),
    do: DateTime.diff(expires_at, now, :day) <= 60

  defp matches?(_item, q) when q in [nil, ""], do: true

  defp matches?(item, q) do
    q = String.downcase(q)
    Enum.any?([item.title, item.barcode, item.serial, item.kind], &contains?(&1, q))
  end

  defp contains?(nil, _q), do: false
  defp contains?(text, q), do: text |> String.downcase() |> String.contains?(q)

  @doc """
  Rows grouped by place, as `{place, rows}`: D4H locations by name, then "With
  members", then "No location". In a place, each item's contents follow it.
  """
  def group(rows) do
    rows
    |> Enum.group_by(& &1.place)
    |> Enum.sort_by(fn {place, _rows} -> {place_order(place), place} end)
    |> Enum.map(fn {place, rows} ->
      {place, Enum.sort_by(rows, &{&1.holder || "", &1.path, &1.item.id})}
    end)
  end

  defp place_order(@with_members), do: 1
  defp place_order(@no_location), do: 2
  defp place_order(_location), do: 0
end
