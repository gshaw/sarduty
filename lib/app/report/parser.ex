defmodule App.Report.Parser do
  @moduledoc """
  Reads a report query into an `App.Report.Query`. Pure, and knows no fields: checking
  names against them is App.Report.Compiler's.

  The clauses come in this order: select, from, where, group by, pivot, order by, limit,
  offset, label, totals. Keywords, functions, and date ranges ignore case.
  """

  alias App.Report.Error
  alias App.Report.Lexer
  alias App.Report.Query

  @clauses ~w(select from where group pivot order limit offset label totals)
  @functions ~w(count sum avg min max year month quarter lower upper days_since)

  @ranges ~w(TODAY THIS_MONTH LAST_MONTH THIS_YEAR LAST_YEAR)
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
    clauses(query, tokens, "from")
  end

  defp subject([{:word, name, line} | rest]), do: {String.downcase(name), line, rest}
  defp subject(tokens), do: fail(tokens, "Name a subject after from, such as from members.")

  # Each clause at most once, in order.
  defp clauses(query, [], _last), do: {query, []}

  defp clauses(query, [{:word, word, line} | _] = tokens, last) do
    clause = String.downcase(word)

    cond do
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

  defp clause_list, do: "where, group by, pivot, order by, limit, offset, label, or totals"
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

    case rest do
      [{:word, word, _} | after_word] ->
        case String.downcase(word) do
          "asc" -> {{expr, :asc}, after_word}
          "desc" -> {{expr, :desc}, after_word}
          _other -> {{expr, :asc}, rest}
        end

      _rest ->
        {{expr, :asc}, rest}
    end
  end

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
