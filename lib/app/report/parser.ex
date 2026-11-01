defmodule App.Report.Parser do
  @moduledoc """
  Reads a report query into an `App.Report.Query`. Pure, and knows no fields: checking
  names against them is App.Report.Compiler's.

  The clauses come in this order: select, from, where, group by, pivot, order by, limit,
  offset, label, totals. The page's clauses follow (#784): search, then each switch and
  filter with its options, then sort, then page. Keywords, functions, and date ranges
  ignore case.
  """

  alias App.Report.Error
  alias App.Report.Lexer
  alias App.Report.Query

  @clauses ~w(select from where group pivot order limit offset label totals)
  @page_clauses ~w(search switch filter sort page)
  # Names a filter can't take: the URL's own words. A sort's name is only the sort's
  # value in the URL, so `sort id` is fine.
  @reserved ~w(q sort page id subdomain all)
  @max_page 500
  @functions ~w(count sum avg min max year month quarter lower upper days_since)

  @ranges ~w(NOW TODAY THIS_MONTH LAST_MONTH THIS_YEAR LAST_YEAR)
  @ranges_with_n ~w(LAST_N_DAYS NEXT_N_DAYS LAST_N_MONTHS)

  @doc "The functions a query can call."
  def functions, do: @functions

  @doc "The date ranges, as written in a query."
  def ranges, do: @ranges ++ Enum.map(@ranges_with_n, &"#{&1}:n")

  @doc "`{:ok, %Query{}}`, or `{:error, %Error{}}` for the first mistake."
  def parse(text) when is_binary(text) do
    with {:ok, tokens} <- Lexer.tokens(text) do
      try do
        {query, []} = query(tokens)
        {:ok, query}
      catch
        {:report_error, error} -> {:error, error}
      end
    end
  end

  defp query([]), do: fail(nil, "Write a query, starting with select.")

  defp query(tokens) do
    tokens = expect_word(tokens, "select", "Start the query with select.")
    {select, tokens} = list(tokens, &expr/1)

    tokens =
      expect_word(
        tokens,
        "from",
        "Add from and a subject after the select, such as from members."
      )

    {from, from_line, tokens} = subject(tokens)
    query = %Query{select: select, from: from, from_line: from_line}
    {query, rest} = clauses(query, tokens, "from")
    {check_page(query), rest}
  end

  defp subject([{:word, name, line} | rest]), do: {String.downcase(name), line, rest}
  defp subject(tokens), do: fail(tokens, "Name a subject after from, such as from members.")

  # Each clause at most once, in order.
  defp clauses(query, [], _last), do: {query, []}

  defp clauses(query, [{:word, word, line} | _] = tokens, last) do
    clause = String.downcase(word)

    cond do
      clause in @page_clauses ->
        page_clauses(query, tokens, nil)

      clause in ["option", "each"] ->
        fail_line(line, "Write #{clause} under a switch or filter.")

      clause not in @clauses ->
        fail(tokens, "Remove #{word}, or start a clause here: #{clause_list()}.")

      order_of(clause) <= order_of(last) ->
        fail_line(
          line,
          "Move #{clause_name(clause)} before #{clause_name(last)}, or write it once."
        )

      true ->
        {query, rest} = clause(clause, query, tl(tokens))
        clauses(query, rest, clause)
    end
  end

  defp clauses(_query, tokens, _last), do: fail(tokens, "Start a clause here: #{clause_list()}.")

  defp clause_list,
    do:
      "where, group by, pivot, order by, limit, offset, label, totals, search, switch, filter, sort, or page"

  defp clause_name("group"), do: "group by"
  defp clause_name("order"), do: "order by"
  defp clause_name(clause), do: clause
  defp order_of(clause), do: Enum.find_index(@clauses, &(&1 == clause))

  defp clause("where", query, tokens) do
    {expr, rest} = expr(tokens)
    {%{query | where: expr}, rest}
  end

  defp clause("group", query, tokens) do
    tokens = expect_word(tokens, "by", "Write group by.")
    {exprs, rest} = list(tokens, &expr/1)
    {%{query | group_by: exprs}, rest}
  end

  defp clause("pivot", query, tokens) do
    {exprs, rest} = list(tokens, &expr/1)
    {%{query | pivot: exprs}, rest}
  end

  defp clause("order", query, tokens) do
    tokens = expect_word(tokens, "by", "Write order by.")
    {items, rest} = list(tokens, &order_item/1)
    {%{query | order_by: items}, rest}
  end

  defp clause("limit", query, [{:number, n, _} | rest]) when is_integer(n),
    do: {%{query | limit: n}, rest}

  defp clause("limit", _query, tokens), do: fail(tokens, "Write a whole number after limit.")

  defp clause("offset", query, [{:number, n, _} | rest]) when is_integer(n),
    do: {%{query | offset: n}, rest}

  defp clause("offset", _query, tokens), do: fail(tokens, "Write a whole number after offset.")

  defp clause("label", query, tokens) do
    {items, rest} = list(tokens, &label_item/1)
    {%{query | labels: items}, rest}
  end

  defp clause("totals", query, tokens), do: {%{query | totals: true}, tokens}

  defp order_item(tokens) do
    {expr, rest} = expr(tokens)
    {dir, rest} = direction(rest)
    {{expr, dir}, rest}
  end

  # asc or desc, then nulls first or nulls last: blanks go where SQLite would put them
  # otherwise, first going up.
  defp direction(tokens) do
    {dir, rest} =
      case lower_words(tokens, 1) do
        ["asc"] -> {:asc, tl(tokens)}
        ["desc"] -> {:desc, tl(tokens)}
        _other -> {:asc, tokens}
      end

    case lower_words(rest, 2) do
      ["nulls", "first"] -> {{dir, :nulls_first}, Enum.drop(rest, 2)}
      ["nulls", "last"] -> {{dir, :nulls_last}, Enum.drop(rest, 2)}
      ["nulls" | _] -> fail(rest, "Write nulls first or nulls last.")
      _other -> {dir, rest}
    end
  end

  # The page's clauses (#784)

  defp page_clauses(query, [], _last),
    do: {%{query | filters: Enum.reverse(query.filters), sorts: Enum.reverse(query.sorts)}, []}

  defp page_clauses(query, [{:word, word, line} | rest] = tokens, last) do
    clause = String.downcase(word)
    if clause not in @page_clauses, do: misplaced(clause, word, tokens, line)
    check_order(clause, last, line)
    {query, rest} = page_clause(clause, query, rest, line)
    page_clauses(query, rest, clause)
  end

  defp page_clauses(_query, tokens, _last),
    do: fail(tokens, "Start a page clause here: #{page_clause_list()}.")

  defp page_clause_list, do: "search, switch, filter, sort, or page"

  defp misplaced(clause, _word, _tokens, line) when clause in ["option", "each"],
    do: fail_line(line, "Write #{clause} under a switch or filter.")

  defp misplaced(clause, _word, _tokens, line) when clause in @clauses,
    do: fail_line(line, "Move #{clause_name(clause)} before the page's clauses.")

  defp misplaced(_clause, word, tokens, _line),
    do: fail(tokens, "Remove #{word}, or start a page clause here: #{page_clause_list()}.")

  defp check_order(clause, last, line) do
    cond do
      page_order(clause) < page_order(last) -> fail_line(line, "Move #{clause} before #{last}.")
      clause in ["search", "page"] and clause == last -> fail_line(line, "Write #{clause} once.")
      true -> :ok
    end
  end

  defp page_order(nil), do: -1
  defp page_order("search"), do: 0
  defp page_order(kind) when kind in ["switch", "filter"], do: 1
  defp page_order("sort"), do: 2
  defp page_order("page"), do: 3

  defp page_clause("search", query, tokens, line) do
    {fields, rest} = list(tokens, &expr/1)
    {%{query | search: fields, search_line: line}, rest}
  end

  defp page_clause(kind, query, tokens, line) when kind in ["switch", "filter"] do
    {name, label, rest} = name_label(tokens, kind, line)
    {flags, rest} = flags(rest, kind, %{required: false, default: nil, more: false})
    filter = Map.merge(flags, %{kind: String.to_existing_atom(kind), name: name, label: label})
    {filter, rest} = choices(Map.merge(filter, %{options: [], each: nil, line: line}), rest)
    {%{query | filters: [filter | query.filters]}, rest}
  end

  defp page_clause("sort", query, tokens, line) do
    {value, label, rest} = name_label(tokens, "sort", line)
    {order, rest} = list(rest, &order_item/1)
    sort = %{value: value, label: label, order: order, line: line}
    {%{query | sorts: [sort | query.sorts]}, rest}
  end

  defp page_clause("page", query, [{:number, n, _} | rest], _line)
       when is_integer(n) and n in 1..@max_page,
       do: {%{query | page: n}, rest}

  defp page_clause("page", _query, _tokens, line),
    do:
      fail_line(
        line,
        "Write how many rows a page shows after page, from 1 to #{@max_page}: page 50."
      )

  # A name for the URL and a label in quotes: `switch activity 'Kind'`.
  defp name_label([{:word, name, _}, {:string, label, _} | rest], kind, line) do
    name = String.downcase(name)

    if name in @reserved and kind != "sort",
      do: fail_line(line, "Name the #{kind} something other than #{name}: the page uses it.")

    {name, label, rest}
  end

  defp name_label(_tokens, kind, line),
    do:
      fail_line(
        line,
        "Write a name and a label in quotes after #{kind}, such as #{kind} when 'When'."
      )

  defp flags([{:word, word, line} | rest] = tokens, kind, flags) do
    case String.downcase(word) do
      "required" ->
        flags(rest, kind, %{flags | required: true})

      "more" when kind == "filter" ->
        flags(rest, kind, %{flags | more: true})

      "more" ->
        fail_line(
          line,
          "Take out more: it puts a filter behind More filters, and tiles always show."
        )

      "default" ->
        {default, rest} = default(rest, line)
        flags(rest, kind, %{flags | default: default})

      _other ->
        {flags, tokens}
    end
  end

  defp flags(tokens, _kind, flags), do: {flags, tokens}

  defp default([{:word, word, _} | rest], _line) do
    if String.upcase(word) == "THIS_YEAR",
      do: {:this_year, rest},
      else: {String.downcase(word), rest}
  end

  defp default([{:number, n, _} | rest], _line) when is_integer(n),
    do: {Integer.to_string(n), rest}

  defp default([{:string, text, _} | rest], _line), do: {text, rest}

  defp default(_tokens, line),
    do: fail_line(line, "Write the value it starts on after default, such as default 2026.")

  # The options and the each under a switch or filter.
  defp choices(filter, [{:word, word, line} | rest] = tokens) do
    case String.downcase(word) do
      "option" ->
        {option, rest} = option(rest, line)
        choices(%{filter | options: [option | filter.options]}, rest)

      "each" ->
        {each, rest} = each(filter, rest, line)
        choices(%{filter | each: each}, rest)

      _other ->
        {%{filter | options: Enum.reverse(filter.options)}, tokens}
    end
  end

  defp choices(filter, tokens), do: {%{filter | options: Enum.reverse(filter.options)}, tokens}

  defp each(%{each: each} = filter, _tokens, line) when each != nil,
    do: fail_line(line, "Write each once in a #{filter.kind}.")

  defp each(%{kind: :switch}, _tokens, line),
    do: fail_line(line, "Write each under a filter: a switch's tiles are its options.")

  defp each(_filter, tokens, line) do
    {expr, rest} = expr(tokens)
    {where, rest} = option_where(rest)
    {%{expr: expr, where: where, line: line}, rest}
  end

  defp option(tokens, line) do
    {value, rest} = option_value(tokens, line)

    {label, rest} =
      case rest do
        [{:string, label, _} | rest] -> {label, rest}
        _rest -> fail_line(line, "Write the option's label in quotes after #{value}.")
      end

    {where, rest} = option_where(rest)
    {sort, rest} = option_sort(rest)
    {%{value: value, label: label, where: where, sort: sort, line: line}, rest}
  end

  defp option_value([{:word, word, _} | rest], line) do
    if String.downcase(word) == "all",
      do: fail_line(line, "Name the option something other than all: All is the menu's own.")

    {String.downcase(word), rest}
  end

  defp option_value([{:number, n, _} | rest], _line) when is_integer(n),
    do: {Integer.to_string(n), rest}

  defp option_value(_tokens, line),
    do: fail_line(line, "Write a name for the URL after option, such as option draft 'Draft'.")

  defp option_where([{:word, word, _} | rest] = tokens) do
    if String.downcase(word) == "where" do
      {where, rest} = expr(rest)
      {where, rest}
    else
      {nil, tokens}
    end
  end

  defp option_where(tokens), do: {nil, tokens}

  # `sort date` or `sort date desc` on an option's line picks the sort with it. A sort
  # clause has a label in quotes after its name, so the two never mix.
  defp option_sort([{:word, word, _}, {:word, value, _} | rest] = tokens) do
    if String.downcase(word) == "sort" and not match?([{:string, _, _} | _], rest) do
      {dir, rest} = option_sort_dir(rest)
      {{String.downcase(value), dir}, rest}
    else
      {nil, tokens}
    end
  end

  defp option_sort(tokens), do: {nil, tokens}

  defp option_sort_dir(tokens) do
    case lower_words(tokens, 1) do
      ["asc"] -> {:asc, tl(tokens)}
      ["desc"] -> {:desc, tl(tokens)}
      _other -> {nil, tokens}
    end
  end

  # What the page's clauses need of each other and of the query, checked once they're all
  # read. Names are checked against the fields later, by the compiler.
  defp check_page(query) do
    query.filters |> Enum.map(& &1.name) |> duplicate("a filter")
    query.sorts |> Enum.map(& &1.value) |> duplicate("a sort")

    case Enum.filter(query.filters, &(&1.kind == :switch)) do
      [_one, two | _] -> fail_line(two.line, "Write one switch: a page has one row of tiles.")
      _one_or_none -> :ok
    end

    Enum.each(query.filters, &check_filter(&1, query.sorts))
    check_paging(query)
    if query.pivot != [], do: check_pivot(query)
    query
  end

  defp check_paging(%{page: nil}), do: :ok

  defp check_paging(query) do
    if query.limit, do: fail_line(nil, "Take out limit: page shows the rows a page at a time.")
    if query.offset, do: fail_line(nil, "Take out offset: page shows the rows a page at a time.")
    :ok
  end

  defp check_pivot(query) do
    case Enum.find(query.filters, &(&1.kind == :switch)) do
      nil -> :ok
      switch -> fail_line(switch.line, "Take out the switch: a report with pivot has no tiles.")
    end

    if query.page, do: fail_line(nil, "Take out page: a report with pivot shows all its rows.")

    case query.sorts do
      [] ->
        :ok

      [sort | _] ->
        fail_line(sort.line, "Take out sort: a report with pivot sorts by its order by.")
    end
  end

  defp duplicate(names, thing) do
    case names -- Enum.uniq(names) do
      [] -> :ok
      [name | _] -> fail_line(nil, "Give #{thing} another name: #{name} is used twice.")
    end
  end

  defp check_filter(filter, sorts) do
    filter.options |> Enum.map(& &1.value) |> duplicate("an option")
    check_choices(filter)
    check_default(filter)

    for %{sort: {value, _dir}, line: line} <- filter.options,
        not Enum.any?(sorts, &(&1.value == value)) do
      fail_line(line, "There is no sort #{value}. Add sort #{value} 'Label' and a field.")
    end
  end

  defp check_choices(%{options: [], each: nil} = filter),
    do: fail_line(filter.line, "Write an option or each under #{filter.kind} #{filter.name}.")

  defp check_choices(_filter), do: :ok

  defp check_default(%{default: :this_year, each: nil} = filter),
    do:
      fail_line(
        filter.line,
        "Write default THIS_YEAR with each year(...), which lists the years."
      )

  defp check_default(%{default: default, each: nil} = filter) when is_binary(default) do
    unless Enum.any?(filter.options, &(&1.value == default)),
      do:
        fail_line(
          filter.line,
          "Start #{filter.name} on one of its options: there is no option #{default}."
        )
  end

  defp check_default(_filter), do: :ok

  defp label_item(tokens) do
    case expr(tokens) do
      {expr, [{:string, text, _} | rest]} -> {{expr, text}, rest}
      {expr, rest} -> fail(rest, "Write the label in quotes after #{Query.text(expr)}.")
    end
  end

  defp list(tokens, item) do
    {first, rest} = item.(tokens)

    case rest do
      [{:symbol, ",", _} | rest] ->
        {more, rest} = list(rest, item)
        {[first | more], rest}

      rest ->
        {[first], rest}
    end
  end

  # Expressions, loosest first: or, and, not, then a comparison.
  defp expr(tokens), do: or_expr(tokens)

  defp or_expr(tokens) do
    {left, rest} = and_expr(tokens)
    binary_loop(left, rest, "or", :or, &and_expr/1)
  end

  defp and_expr(tokens) do
    {left, rest} = not_expr(tokens)
    binary_loop(left, rest, "and", :and, &not_expr/1)
  end

  defp binary_loop(left, [{:word, word, line} | rest] = tokens, keyword, op, next) do
    if String.downcase(word) == keyword do
      {right, rest} = next.(rest)
      binary_loop({:op, op, left, right, line}, rest, keyword, op, next)
    else
      {left, tokens}
    end
  end

  defp binary_loop(left, tokens, _keyword, _op, _next), do: {left, tokens}

  defp not_expr([{:word, word, line} | rest] = tokens) do
    if String.downcase(word) == "not" do
      {expr, rest} = not_expr(rest)
      {{:not, expr, line}, rest}
    else
      comparison(tokens)
    end
  end

  defp not_expr(tokens), do: comparison(tokens)

  @comparisons %{
    "=" => :eq,
    "!=" => :ne,
    "<>" => :ne,
    "<" => :lt,
    ">" => :gt,
    "<=" => :le,
    ">=" => :ge
  }

  defp comparison(tokens) do
    {left, rest} = primary(tokens)
    comparison_tail(left, rest)
  end

  defp comparison_tail(left, [{:symbol, symbol, line} | rest])
       when is_map_key(@comparisons, symbol) do
    {right, rest} = primary(rest)
    {{:op, Map.fetch!(@comparisons, symbol), left, right, line}, rest}
  end

  defp comparison_tail(left, [{:word, word, line} | rest] = tokens),
    do: word_tail(String.downcase(word), left, rest, line, tokens)

  defp comparison_tail(left, tokens), do: {left, tokens}

  @matches %{"contains" => :contains, "like" => :like}
  @lists %{"includes" => :includes, "excludes" => :excludes}

  defp word_tail("is", left, rest, line, _tokens) do
    case lower_words(rest, 2) do
      ["not", "null"] -> {{:is_null, left, true, line}, Enum.drop(rest, 2)}
      ["null" | _] -> {{:is_null, left, false, line}, Enum.drop(rest, 1)}
      _other -> fail_line(line, "Write is null or is not null.")
    end
  end

  defp word_tail("in", left, rest, line, _tokens) do
    {items, rest} = items(rest, line)
    {{:in, left, items, false, line}, rest}
  end

  defp word_tail("not", left, rest, line, tokens) do
    case lower_words(rest, 1) do
      ["in"] ->
        negate_in(word_tail("in", left, tl(rest), line, tokens))

      [word] when is_map_key(@matches, word) ->
        negate(word_tail(word, left, tl(rest), line, tokens))

      _other ->
        {left, tokens}
    end
  end

  defp word_tail(kind, left, rest, line, _tokens) when kind in ["includes", "excludes"] do
    {items, rest} = items(rest, line)
    {{Map.fetch!(@lists, kind), left, items, line}, rest}
  end

  defp word_tail(word, left, rest, line, _tokens) when is_map_key(@matches, word) do
    {right, rest} = primary(rest)
    {{:op, Map.fetch!(@matches, word), left, right, line}, rest}
  end

  defp word_tail(word, left, rest, line, _tokens) when word in ["starts", "ends"] do
    if lower_words(rest, 1) != ["with"], do: fail_line(line, "Write #{word} with.")
    {right, rest} = primary(tl(rest))
    op = if word == "starts", do: :starts_with, else: :ends_with
    {{:op, op, left, right, line}, rest}
  end

  defp word_tail(_word, left, _rest, _line, tokens), do: {left, tokens}

  defp negate_in({{:in, left, items, false, line}, rest}),
    do: {{:in, left, items, true, line}, rest}

  defp negate({expr, rest}), do: {{:not, expr, Query.line(expr)}, rest}

  defp lower_words(tokens, n) do
    tokens
    |> Enum.take(n)
    |> Enum.map(fn
      {:word, word, _line} -> String.downcase(word)
      _other -> nil
    end)
  end

  defp items([{:symbol, "(", _} | rest], _line) do
    {items, rest} = list(rest, &primary/1)

    case rest do
      [{:symbol, ")", _} | rest] -> {items, rest}
      rest -> fail(rest, "Close the list with ).")
    end
  end

  defp items(_tokens, line), do: fail_line(line, "Put the list in brackets: ('Callout', 'Rope').")

  defp primary([{:number, n, line} | rest]), do: {{:literal, n, line}, rest}
  defp primary([{:string, text, line} | rest]), do: {{:literal, text, line}, rest}
  defp primary([{:value, name, line} | rest]), do: {{:value, name, line}, rest}

  defp primary([{:symbol, "(", _} | rest]) do
    case expr(rest) do
      {expr, [{:symbol, ")", _} | rest]} -> {expr, rest}
      {_expr, rest} -> fail(rest, "Close the bracket with ).")
    end
  end

  defp primary([{:symbol, "*", line} | _rest]),
    do: fail_line(line, "Name the fields to show: a report cannot select *.")

  defp primary([{:word, word, line} | rest] = tokens),
    do: word(String.downcase(word), tokens, rest, line)

  defp primary(tokens), do: fail(tokens, "Write a field or a value here.")

  defp word("true", _tokens, rest, line), do: {{:literal, true, line}, rest}
  defp word("false", _tokens, rest, line), do: {{:literal, false, line}, rest}
  defp word("null", _tokens, rest, line), do: {{:literal, nil, line}, rest}
  defp word("date", _tokens, [{:string, _, _} | _] = rest, line), do: date(rest, line)
  defp word(lower, tokens, rest, line), do: named(lower, String.upcase(lower), tokens, rest, line)

  defp named(_lower, upper, _tokens, rest, line) when upper in @ranges,
    do: {{:range, upper, nil, line}, rest}

  defp named(_lower, upper, _tokens, rest, line) when upper in @ranges_with_n,
    do: range_n(upper, rest, line)

  defp named(lower, _upper, _tokens, [{:symbol, "(", _} | rest], line) when lower in @functions,
    do: call(lower, rest, line)

  defp named(lower, _upper, tokens, _rest, _line) when lower in @clauses,
    do: fail(tokens, "Write a field or value before #{lower}.")

  defp named(_lower, _upper, tokens, _rest, _line), do: field(tokens)

  defp date([{:string, text, _} | rest], line) do
    case Date.from_iso8601(text) do
      {:ok, date} -> {{:literal, date, line}, rest}
      {:error, _} -> fail_line(line, "Write the date as date '2026-01-01'.")
    end
  end

  defp range_n(name, [{:symbol, ":", _}, {:number, n, _} | rest], line)
       when is_integer(n) and n > 0,
       do: {{:range, name, n, line}, rest}

  defp range_n(name, _tokens, line),
    do: fail_line(line, "Write a number of days or months after #{name}, such as #{name}:30.")

  defp call(name, [{:word, word, _} | rest] = tokens, line) do
    if String.downcase(word) == "distinct" do
      {args, rest} = args(rest, line)
      {{:call, name, true, args, line}, rest}
    else
      {args, rest} = args(tokens, line)
      {{:call, name, false, args, line}, rest}
    end
  end

  defp call(name, tokens, line) do
    {args, rest} = args(tokens, line)
    {{:call, name, false, args, line}, rest}
  end

  defp args([{:symbol, ")", _} | rest], _line), do: {[], rest}

  defp args(tokens, _line) do
    {args, rest} = list(tokens, &expr/1)

    case rest do
      [{:symbol, ")", _} | rest] -> {args, rest}
      rest -> fail(rest, "Close the bracket with ).")
    end
  end

  # A field is names joined by dots, and a roll-up field takes its arguments in brackets.
  defp field([{:word, word, line} | rest]) do
    {path, rest} = path_rest(rest, [word])

    case rest do
      [{:symbol, "(", _} | rest] ->
        {args, rest} = args(rest, line)
        {{:field, path, args, line}, rest}

      rest ->
        {{:field, path, [], line}, rest}
    end
  end

  defp path_rest([{:symbol, ".", _}, {:word, word, _} | rest], acc),
    do: path_rest(rest, [word | acc])

  defp path_rest([{:symbol, ".", line} | _], _acc),
    do: fail_line(line, "Write a field name after the dot, such as member.name.")

  defp path_rest(rest, acc), do: {Enum.reverse(acc), rest}

  defp expect_word([{:word, word, _} | rest] = tokens, keyword, message) do
    if String.downcase(word) == keyword, do: rest, else: fail(tokens, message)
  end

  defp expect_word(tokens, _keyword, message), do: fail(tokens, message)

  defp fail([token | _], message), do: fail_line(elem(token, 2), message)
  defp fail(_none, message), do: fail_line(nil, message)

  defp fail_line(line, message), do: throw({:report_error, Error.new(line, message)})
end
