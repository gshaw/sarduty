defmodule App.Report do
  # cspell:ignore SOQL
  @moduledoc """
  Reports (#768): saved queries in a small language, run on one team's records.

  The language is Google Sheets' QUERY language plus four pieces of Salesforce's SOQL:
  `from`, dotted fields to a parent, date ranges, and `:name` values. A query reads one
  team's fields from App.Report.Catalog and nothing else. Clauses after the query draw
  its page (#784): a search box, tiles, filters, sortable headers, and pages. Each pick
  becomes a plain query (App.Report.Picks). See docs/reports.md.
  """

  alias App.Model.Team
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Parser
  alias App.Report.Picks
  alias App.Report.Query
  alias App.Report.Runner
  alias App.Report.Value
  alias App.Report.View

  @doc """
  Runs `text` on `team`'s records: `{:ok, %App.Report.Result{}}`, or
  `{:error, %App.Report.Error{}}` for a mistake, checked before anything runs. `given`
  holds picked values by name, and the page's picks: every row they keep, not a page.
  """
  def run(text, %Team{} = team, given \\ %{}, now \\ DateTime.utc_now()) do
    context = Context.new(team, now)

    with {:ok, query} <- Parser.parse(text),
         :ok <- check_page(query, context, given) do
      picks = Picks.resolve(query, given, context.today)

      with {:ok, plan} <- query |> Picks.plain(picks) |> Compiler.compile(context, picks.given) do
        Runner.run(plan, team.timezone)
      end
    end
  end

  @doc "Checks `text` against `team`'s fields without running it: `{:ok, plan}` or `{:error, error}`."
  def check(text, %Team{} = team, given \\ %{}, now \\ DateTime.utc_now()) do
    context = Context.new(team, now)

    with {:ok, query} <- Parser.parse(text),
         :ok <- check_page(query, context, given) do
      picks = Picks.resolve(query, given, context.today)
      query |> Picks.plain(picks) |> Compiler.compile(context, picks.given)
    end
  end

  @doc """
  Runs `text` as a page (#784): `{:ok, %App.Report.View{}}` with one page of rows, the
  total, each tile's count, and each control's menu, or `{:error, %App.Report.Error{}}`.
  `given` is the URL's params: the values, the picks, `q`, `sort`, and `page`.
  """
  def page(text, %Team{} = team, given \\ %{}, now \\ DateTime.utc_now()) do
    context = Context.new(team, now)

    with {:ok, query} <- Parser.parse(text),
         :ok <- check_page(query, context, given),
         {:ok, menus} <- menus(query, context),
         {:ok, starts} <- starts(query, given, menus, context) do
      picks = Picks.resolve(query, given, context.today, menus)
      build_view(query, picks, menus, starts, context)
    end
  end

  # What each control starts on, whatever the URL picks, so a URL leaves it out: the sort
  # without one in the URL, and a required filter's value's own default, such as this year.
  defp starts(query, given, menus, context) do
    sort = Picks.resolve(query, Map.delete(given, "sort"), context.today, menus).sort

    start =
      Picks.resolve(
        query,
        Map.drop(given, Enum.map(query.filters, & &1.name)),
        context.today,
        menus
      )

    if Enum.any?(start.filters, &(elem(&1, 1) == :each_default)) do
      with {:ok, plan} <-
             query |> Picks.plain(start) |> Compiler.compile(context, start.given) do
        {:ok, %{sort: sort, values: Map.new(plan.values, &{&1.name, Value.param(&1)})}}
      end
    else
      {:ok, %{sort: sort, values: %{}}}
    end
  end

  defp build_view(query, picks, menus, starts, context) do
    with {:ok, switch} <- switch(query, picks, context),
         {:ok, total, page} <- total(query, picks, switch, context),
         {:ok, plan} <- rows_plan(query, picks, page, context),
         {:ok, result} <- Runner.run(plan, context.timezone) do
      view = %View{
        result: result,
        total: total || length(result.rows),
        page: page,
        switch: switch
      }

      {:ok, controls(view, query, picks, menus, starts, context)}
    end
  end

  defp controls(view, query, picks, menus, starts, context) do
    filters =
      Enum.flat_map(query.filters, &filter_menu(&1, picks, menus, view.result, starts, context))

    defaults = query |> defaults(filters) |> Map.put("sort", starts.sort)

    %{
      view
      | filters: filters,
        defaults: defaults,
        search?: query.search != [],
        q: picks.q,
        sorts: sorts(query, view.result),
        sort: picks.sort,
        values: plain_values(query, view.result),
        params: params(picks, query, defaults, view.result)
    }
  end

  # The query's own `:name` values, not the controls'.
  defp plain_values(query, result) do
    owned = ["q" | Enum.map(query.filters, & &1.name)]
    Enum.reject(result.values, &(&1.name in owned))
  end

  # With page, the count of every row first, so the page is never past the last.
  defp total(%Query{page: nil}, _picks, _switch, _context), do: {:ok, nil, nil}

  defp total(query, picks, switch, context) do
    with {:ok, n} <- picked_count(query, picks, switch, context) do
      pages = max(div(n + query.page - 1, query.page), 1)
      number = min(picks.page, pages)

      {:ok, n,
       %App.Page{page_number: number, page_size: query.page, total_pages: pages, total_entries: n}}
    end
  end

  defp rows_plan(query, picks, page, context) do
    query
    |> Picks.plain(picks, page: page && {page.page_number, page.page_size})
    |> Compiler.compile(context, picks.given)
  end

  defp count(plain, picks, context) do
    with {:ok, sql} <- Compiler.count(plain, context, picks.given), do: Runner.count(sql)
  end

  # With no search, the picked tile has already counted every row.
  defp picked_count(query, %{q: ""} = picks, %{picked: picked, tiles: tiles}, context) do
    case Enum.find(tiles, &(&1.value == picked)) do
      nil -> count(Picks.plain(query, picks), picks, context)
      tile -> {:ok, tile.count}
    end
  end

  defp picked_count(query, picks, _switch, context),
    do: count(Picks.plain(query, picks), picks, context)

  # Each tile counts its rows with every other pick on and the search off.
  defp switch(query, picks, context) do
    case Enum.find(query.filters, &(&1.kind == :switch)) do
      nil -> {:ok, nil}
      switch -> tiles(query, switch, picks, context)
    end
  end

  defp tiles(query, switch, picks, context) do
    all = if switch.required, do: [], else: [{"all", "All", :all}]
    options = Enum.map(switch.options, &{&1.value, &1.label, {:option, &1}})

    with {:ok, tiles} <- counts(all ++ options, query, picks, context) do
      picked = Picks.value(picks.filters[switch.name]) || "all"
      {:ok, %{name: switch.name, label: switch.label, picked: picked, tiles: tiles}}
    end
  end

  # One pass counts every tile; a query that groups counts each tile's groups on its own.
  defp counts(tiles, query, picks, context) do
    base = Picks.plain(query, picks, switch: :all, search: false)
    wheres = Enum.map(tiles, fn {_value, _label, pick} -> tile_where(pick) end)

    case Compiler.counts(base, wheres, context, picks.given) do
      {:ok, sql} ->
        with {:ok, ns} <- Runner.counts(sql) do
          {:ok,
           Enum.zip_with(tiles, ns, fn {value, label, _pick}, n ->
             %{value: value, label: label, count: n}
           end)}
        end

      :grouped ->
        each_count(tiles, query, picks, context)

      error ->
        error
    end
  end

  defp tile_where(:all), do: nil
  defp tile_where({:option, option}), do: option.where

  defp each_count(tiles, query, picks, context) do
    tiles
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, []}, fn {value, label, pick}, {:ok, acc} ->
      plain = Picks.plain(query, picks, switch: pick, search: false)

      case count(plain, picks, context) do
        {:ok, n} -> {:cont, {:ok, [%{value: value, label: label, count: n} | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  defp filter_menu(%{kind: :switch}, _picks, _menus, _result, _starts, _context), do: []

  defp filter_menu(filter, picks, menus, result, starts, context) do
    all = if filter.required, do: [], else: [{"All", "all"}]
    options = Enum.map(filter.options, &{&1.label, &1.value})
    each = Map.get(menus, filter.name, [])

    [
      %{
        name: filter.name,
        label: filter.label,
        picked: picked(picks.filters[filter.name], filter.name, result),
        default: filter_default(filter, context, starts),
        more: filter.more,
        options: all ++ options ++ each
      }
    ]
  end

  # What a pick shows: a required filter with nothing picked shows the value's default.
  defp picked(:each_default, name, result), do: value_param(result, name)
  defp picked(pick, _name, _result), do: Picks.value(pick)

  defp value_param(result, name) do
    case Enum.find(result.values, &(&1.name == name)) do
      nil -> nil
      value -> Value.param(value)
    end
  end

  defp filter_default(filter, context, starts) do
    cond do
      filter.default == :this_year -> Integer.to_string(context.today.year)
      filter.default -> filter.default
      not filter.required -> "all"
      filter.options != [] -> hd(filter.options).value
      true -> Map.get(starts.values, filter.name)
    end
  end

  defp defaults(query, filters) do
    switch =
      for %{kind: :switch} = s <- query.filters, into: %{} do
        cond do
          s.default -> {s.name, s.default}
          s.required -> {s.name, hd(s.options).value}
          true -> {s.name, "all"}
        end
      end

    filters |> Map.new(&{&1.name, &1.default}) |> Map.merge(switch)
  end

  defp params(picks, query, defaults, result) do
    values = Map.new(result.values, &{&1.name, Value.param(&1)})

    controls =
      for filter <- query.filters, value = Picks.value(picks.filters[filter.name]), into: %{} do
        {filter.name, value}
      end

    values
    |> Map.merge(controls)
    |> Map.merge(%{"q" => picks.q, "sort" => picks.sort, "page" => picks.page})
    |> Map.reject(fn {name, value} ->
      value in [nil, ""] or Map.get(defaults, name) == value or (name == "page" and value == 1)
    end)
  end

  # Header sorts by column: a sort belongs to the column with its label, or the one that
  # shows its first field.
  defp sorts(%Query{sorts: []}, _result), do: %{}

  defp sorts(query, result) do
    columns = query.select |> Enum.zip(result.columns) |> Enum.with_index()

    Map.new(query.sorts, fn sort ->
      {_, i} = Enum.find(columns, &sort_column?(sort, &1))
      {i, arrows(sort)}
    end)
  end

  defp sort_column?(sort, {{ast, column}, _i}) do
    [{first, _} | _] = sort.order

    String.downcase(sort.label) == String.downcase(column.label || "") or
      Query.same?(first, ast)
  end

  defp arrows(sort) do
    case Picks.written(sort) do
      :asc -> [{"↑", sort.value}, {"↓", sort.value <> "-"}]
      :desc -> [{"↓", sort.value}, {"↑", sort.value <> "-"}]
    end
  end

  # Each filter's `each` values, read once per page.
  defp menus(query, context) do
    query.filters
    |> Enum.filter(& &1.each)
    |> Enum.reduce_while({:ok, %{}}, fn filter, {:ok, acc} ->
      case each_menu(query, filter, context) do
        {:ok, menu} -> {:cont, {:ok, Map.put(acc, filter.name, menu)}}
        {:error, error} -> {:halt, {:error, Error.in_part(error, "filter #{filter.name}")}}
      end
    end)
  end

  defp each_menu(query, filter, context) do
    case query |> Picks.clear() |> Compiler.values(filter.each.expr, context) do
      {:ok, {:choices, choices}} ->
        {:ok, choices}

      {:ok, {:sql, sql, type}} ->
        with {:ok, values} <- Runner.values(sql, type),
             do: {:ok, each_choices(values, type, context)}

      error ->
        error
    end
  end

  defp each_choices(values, :year, context),
    do:
      [context.today.year | values]
      |> Enum.uniq()
      |> Enum.sort(:desc)
      |> Enum.map(&{Integer.to_string(&1), Integer.to_string(&1)})

  defp each_choices(values, :month, _context),
    do: values |> Enum.sort() |> Enum.map(&{Runner.month_name(&1), Integer.to_string(&1)})

  defp each_choices(values, :quarter, _context),
    do: values |> Enum.sort() |> Enum.map(&{"Q#{&1}", Integer.to_string(&1)})

  defp each_choices(values, :number, _context),
    do: values |> Enum.sort() |> Enum.map(&{Service.Format.number(&1), to_string(&1)})

  defp each_choices(values, _type, _context),
    do: values |> Enum.sort_by(&String.downcase/1) |> Enum.map(&{&1, &1})

  # Every part of the page is checked as the query's own is, before anything runs, and
  # a mistake names its part: "Line 5, option draft: …".
  defp check_page(%Query{} = query, context, given) do
    if Query.page_clauses?(query), do: check_parts(query, context, given), else: :ok
  end

  defp check_parts(query, context, given) do
    base = Picks.clear(query)

    with {:ok, plan} <- Compiler.compile(base, context, given),
         :ok <- check_required(query),
         :ok <- check_search(base, query, context, given),
         :ok <- check_filters(base, query, context, given) do
      check_sorts(base, query, plan, context, given)
    end
  end

  defp check_required(query) do
    read = values_read(Picks.clear(query))

    case Enum.find(query.filters, &(not &1.required and &1.name in read)) do
      nil ->
        :ok

      filter ->
        {:error,
         Error.new(
           filter.line,
           "Write required after #{filter.kind} #{filter.name}: the query reads :#{filter.name}, so it always needs a pick."
         )}
    end
  end

  # The `:name` values a query compares with, not those a field takes as an argument.
  defp values_read(query) do
    [
      query.select,
      query.where,
      query.group_by,
      query.pivot,
      Enum.map(query.order_by, &elem(&1, 0))
    ]
    |> List.flatten()
    |> Enum.flat_map(&names/1)
  end

  defp names({:value, name, _line}), do: [name]
  defp names({:field, _path, _args, _line}), do: []
  defp names(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.flat_map(&names/1)
  defp names(list) when is_list(list), do: Enum.flat_map(list, &names/1)
  defp names(_other), do: []

  defp check_search(_base, %{search: []}, _context, _given), do: :ok

  defp check_search(base, query, context, given) do
    picks = %Picks{q: "x"}
    plain = Picks.plain(%{base | search: query.search, search_line: query.search_line}, picks)
    part(Compiler.compile(plain, context, Map.put(given, "q", "x")), "search")
  end

  defp check_filters(base, query, context, given) do
    Enum.reduce_while(query.filters, :ok, fn filter, :ok ->
      case check_filter(base, filter, context, given) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_filter(base, filter, context, given) do
    options =
      for %{where: where} = option <- filter.options, where != nil do
        {where, Map.put(given, filter.name, option.value), "option #{option.value}"}
      end

    each =
      if filter.each && filter.each.where,
        do: [{filter.each.where, Map.delete(given, filter.name), "filter #{filter.name}"}],
        else: []

    with :ok <- check_each(base, filter, context) do
      check_wheres(base, options ++ each, context)
    end
  end

  defp check_each(_base, %{each: nil}, _context), do: :ok

  defp check_each(base, filter, context),
    do: part(Compiler.values(base, filter.each.expr, context), "filter #{filter.name}")

  defp check_wheres(base, wheres, context) do
    Enum.reduce_while(wheres, :ok, fn {where, given, part}, :ok ->
      plain = %{base | where: and_where(base.where, where)}

      case part(Compiler.compile(plain, context, given), part) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp and_where(nil, where), do: where
  defp and_where(base, where), do: {:op, :and, base, where, Query.line(where)}

  defp check_sorts(base, query, plan, context, given) do
    Enum.reduce_while(query.sorts, :ok, fn sort, :ok ->
      with :ok <-
             part(
               Compiler.compile(%{base | order_by: sort.order}, context, given),
               "sort #{sort.value}"
             ),
           :ok <- sort_column(sort, base, plan) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp sort_column(sort, base, plan) do
    columns = base.select |> Enum.zip(plan.columns) |> Enum.with_index()

    if Enum.any?(columns, &sort_column?(sort, &1)) do
      :ok
    else
      labels = Enum.map_join(plan.columns, ", ", &"'#{&1.label}'")

      {:error,
       %Error{
         line: sort.line,
         part: "sort #{sort.value}",
         message: "Label it like the column it sorts, one of #{labels}, or show its field."
       }}
    end
  end

  defp part({:ok, _plan}, _part), do: :ok
  defp part({:error, error}, part), do: {:error, Error.in_part(error, part)}
end
