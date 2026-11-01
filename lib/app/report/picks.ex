defmodule App.Report.Picks do
  @moduledoc """
  What a page's controls say (#784): each switch's and filter's pick, the search, the
  sort, and the page, read from the URL's params. `plain/3` turns them into a plain query
  for App.Report.Compiler, so a pick is never more than a `where` and an `order by`. Pure.

  - `filters`: by name, `:all`, `{:option, option}`, `{:each, value}`, or `:each_default`
    (a required filter with nothing picked: the value's own default, such as this year)
  - `given`: the values the query runs with, the URL's and the picks'
  - `sort`: the sort the rows have, as the URL writes it (`"date"` or `"date-"`), or nil
  """

  alias App.Report.Query

  defstruct filters: %{}, q: "", sort: nil, page: 1, given: %{}

  @doc """
  The picks `params` say for `query`'s controls. `menus` holds each filter's `each`
  values by name, when the page has read them: a value not among them is no pick.
  """
  def resolve(%Query{} = query, params, %Date{} = today, menus \\ %{}) do
    filters = Map.new(query.filters, &{&1.name, pick(&1, params, today, menus)})
    q = params |> Map.get("q", "") |> to_string() |> String.trim()

    %__MODULE__{
      filters: filters,
      q: q,
      sort: sort_value(query, params, filters),
      page: page_number(params["page"]),
      given: given(params, query, filters, q)
    }
  end

  defp pick(filter, params, today, menus) do
    raw = blank(params[filter.name]) || default(filter.default, today)
    option = Enum.find(filter.options, &(&1.value == raw))

    cond do
      option -> {:option, option}
      raw in [nil, "all"] and not filter.required -> :all
      raw not in [nil, "all"] and in_menu?(filter, raw, menus) -> {:each, raw}
      filter.required -> first(filter)
      true -> :all
    end
  end

  defp in_menu?(%{each: nil}, _raw, _menus), do: false

  defp in_menu?(filter, raw, menus) do
    case Map.fetch(menus, filter.name) do
      {:ok, values} -> Enum.any?(values, &(elem(&1, 1) == raw))
      :error -> true
    end
  end

  defp first(%{options: [option | _]}), do: {:option, option}
  defp first(_filter), do: :each_default

  defp default(:this_year, today), do: Integer.to_string(today.year)
  defp default(default, _today), do: default

  defp blank(nil), do: nil
  defp blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp blank(value), do: to_string(value)

  defp page_number(text) when is_binary(text) do
    case Integer.parse(text) do
      {n, ""} when n > 0 -> n
      _other -> 1
    end
  end

  defp page_number(n) when is_integer(n) and n > 0, do: n
  defp page_number(_other), do: 1

  # The URL's values, then each pick's: a filter at All gives none, so a query that reads
  # its name gets the value's default.
  defp given(params, query, filters, q) do
    controls = Enum.map(query.filters, & &1.name) ++ ["q", "sort", "page"]

    params
    |> Map.drop(controls)
    |> Map.merge(
      for {name, pick} <- filters, value = picked_value(pick), value != nil, into: %{} do
        {name, value}
      end
    )
    |> then(&if(query.search != [], do: Map.put(&1, "q", q), else: &1))
  end

  @doc "A pick's value as the URL writes it: `\"all\"` for All, nil for a default."
  def value(:all), do: "all"
  def value(pick), do: picked_value(pick)

  defp picked_value({:option, option}), do: option.value
  defp picked_value({:each, value}), do: value
  defp picked_value(_pick), do: nil

  # Sorts

  defp sort_value(query, params, filters) do
    cond do
      sort = find_sort(query, params["sort"]) -> sort
      sort = option_sort(query, filters) -> sort
      true -> inferred_sort(query)
    end
  end

  defp find_sort(_query, value) when not is_binary(value), do: nil

  defp find_sort(query, value) do
    key = String.trim_trailing(value, "-")
    if Enum.any?(query.sorts, &(&1.value == key)), do: value
  end

  # The first picked option that picks a sort: Future sorts oldest first.
  defp option_sort(query, filters),
    do: Enum.find_value(query.filters, &picked_sort(query, filters[&1.name]))

  defp picked_sort(query, {:option, %{sort: {value, dir}}}) do
    case Enum.find(query.sorts, &(&1.value == value)) do
      nil -> nil
      sort -> if dir in [nil, written(sort)], do: value, else: value <> "-"
    end
  end

  defp picked_sort(_query, _pick), do: nil

  # The query's own order by, when it is one of the sorts.
  defp inferred_sort(%Query{order_by: [{expr, dir} | _]} = query) do
    case Enum.find(query.sorts, fn %{order: [{first, _} | _]} -> Query.same?(first, expr) end) do
      nil -> nil
      sort -> if base(dir) == written(sort), do: sort.value, else: sort.value <> "-"
    end
  end

  defp inferred_sort(_query), do: nil

  @doc "The direction a sort's first field goes as written: `:asc` or `:desc`."
  def written(%{order: [{_expr, dir} | _]}), do: base(dir)

  defp base({dir, _nulls}), do: dir
  defp base(dir), do: dir

  defp flip({dir, nulls}), do: {flip(dir), nulls}
  defp flip(:asc), do: :desc
  defp flip(:desc), do: :asc

  # The plain query

  @doc """
  The plain query for `picks`: the query's `where` and each pick's, the search's, and
  the sort's `order by`. Options:

  - `search: false` leaves the search out, as a switch's tiles count
  - `switch: pick` counts the switch at `pick` instead of its own
  - `paged: true` adds the page's `limit` and `offset`, given as `page: {n, size}`, and
    sorts by `id` last so no row lands on two pages
  """
  def plain(%Query{} = query, %__MODULE__{} = picks, opts \\ []) do
    filters = switched(query, picks.filters, opts)
    search = search(query, picks.q, Keyword.get(opts, :search, true))
    conditions = Enum.flat_map(query.filters, &condition(&1, filters[&1.name])) ++ search
    where = and_all([query.where | conditions])
    paged(%{clear(query) | where: where, order_by: order(query, picks.sort)}, opts[:page])
  end

  defp switched(query, filters, opts) do
    case Keyword.fetch(opts, :switch) do
      {:ok, pick} -> Map.put(filters, switch_name(query), pick)
      :error -> filters
    end
  end

  defp paged(plain, nil), do: plain

  defp paged(plain, {n, size}),
    do: %{plain | order_by: tie_break(plain), limit: size, offset: (n - 1) * size}

  @doc "The query without its page's clauses."
  def clear(%Query{} = query), do: %{query | search: [], filters: [], sorts: [], page: nil}

  @doc "The switch's name, or nil."
  def switch_name(query),
    do: Enum.find_value(query.filters, &(&1.kind == :switch && &1.name))

  defp condition(_filter, :all), do: []
  defp condition(_filter, {:option, %{where: nil}}), do: []
  defp condition(_filter, {:option, %{where: where}}), do: [where]
  defp condition(%{each: %{where: where}}, pick) when where != nil and pick != :all, do: [where]
  defp condition(_filter, _pick), do: []

  # The search box ORs `contains :q` over its fields.
  defp search(%{search: []}, _q, _on?), do: []
  defp search(_query, "", _on?), do: []
  defp search(_query, _q, false), do: []

  defp search(query, _q, true) do
    line = query.search_line

    [
      query.search
      |> Enum.map(&{:op, :contains, &1, {:value, "q", line}, line})
      |> Enum.reduce(fn right, left -> {:op, :or, left, right, line} end)
    ]
  end

  defp and_all(conditions) do
    case Enum.reject(conditions, &is_nil/1) do
      [] -> nil
      [one | rest] -> Enum.reduce(rest, one, &{:op, :and, &2, &1, Query.line(&1)})
    end
  end

  defp order(query, nil), do: query.order_by

  defp order(query, value) do
    key = String.trim_trailing(value, "-")
    [{first, dir} | rest] = Enum.find(query.sorts, &(&1.value == key)).order
    if String.ends_with?(value, "-"), do: [{first, flip(dir)} | rest], else: [{first, dir} | rest]
  end

  # Rows that sort the same keep one order across pages: by id, or a grouped report's
  # groups.
  defp tie_break(%Query{group_by: [], order_by: order}) do
    id = {:field, ["id"], [], nil}

    if Enum.any?(order, fn {e, _} -> Query.same?(e, id) end),
      do: order,
      else: List.insert_at(order, -1, {id, :asc})
  end

  defp tie_break(%Query{group_by: groups, order_by: order}) do
    missing =
      Enum.reject(groups, fn g -> Enum.any?(order, fn {e, _} -> Query.same?(e, g) end) end)

    order ++ Enum.map(missing, &{&1, :asc})
  end
end
