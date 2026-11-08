defmodule App.Document.Parser do
  @moduledoc """
  Reads a document's text into an `App.Document` (#918), or a form's (#950). Pure, and
  knows no fields: App.Document.Checker checks names against the catalog.

  A clause starts at the left edge, and the lines indented under it are its own. Its
  words are App.Report.Lexer's tokens, a report is App.Report.Parser's query, and every
  value is App.Report.Parser's expression, arithmetic and all, with five additions read
  here: `'text {value}'` puts a value in text, `value as format` formats it, `value if
  condition` is blank when the condition is false, `if condition then value else value`
  picks one, and `rate on date` reads a const on a date. A form's `rows` place holds a
  row's places, indented under it, and `fill each people into rows` fills them.
  """

  alias App.Document
  alias App.Report.Error
  alias App.Report.Lexer
  # The report language's parser: this module reads only what a document adds.
  alias App.Report.Parser
  alias App.Report.Query

  @clauses ~w(document form about for report const ask compute title lock keep page places fill
               expect)
  @starts ~w(member year)
  @repeated ~w(report const ask compute fill expect)
  @kinds %{
    "text" => :text,
    "image" => :image,
    "flow" => :flow,
    "tick" => :tick,
    "rows" => :rows
  }
  @aligns %{"left" => :left, "right" => :right, "center" => :center}
  @lengths ~w(top left right bottom width height size leading gap pad pitch indent)
  @ask_options ~w(remember default choose hint)
  @units %{"in" => 72, "pt" => 1, "mm" => 72 / 25.4}
  @image_options ~w(width height pad)
  # Each option's atom, written out: to_existing_atom fails until some module loads `:pad`.
  @atoms Map.new(@lengths, &{&1, String.to_atom(&1)})

  @doc "The clauses, in the order a document writes them."
  def clauses, do: @clauses

  @doc "`{:ok, %Document{}}`, or `{:error, %Error{}}` for the first mistake."
  def parse(text) when is_binary(text) do
    text
    |> lines()
    |> blocks()
    |> Enum.reduce({%Document{}, nil}, &clause/2)
    |> elem(0)
    |> finish()
  catch
    {:report_error, %Error{} = error} -> {:error, error}
  end

  # Each line that holds more than a comment, as `{number, indent, text}`.
  defp lines(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, _n} -> String.trim(line) == "" or comment?(line) end)
    |> Enum.map(fn {line, n} ->
      body = String.trim_leading(line)
      {n, String.length(line) - String.length(body), body}
    end)
  end

  defp comment?(line), do: line |> String.trim_leading() |> String.starts_with?("--")

  # A clause's first line and the lines under it.
  defp blocks([]), do: fail(nil, "Write a document, starting with document 'Its name'.")

  defp blocks([{n, indent, _text} | _]) when indent > 0,
    do: fail(n, "Start the clause at the left edge, with no space before it.")

  defp blocks(lines), do: groups(lines, 0)

  # Lines split where one starts at `indent`; deeper lines belong to the one above.
  defp groups(lines, indent) do
    lines
    |> Enum.chunk_while(
      [],
      fn
        {_n, ^indent, _text} = line, [] -> {:cont, [line]}
        {_n, ^indent, _text} = line, acc -> {:cont, Enum.reverse(acc), [line]}
        line, acc -> {:cont, [line | acc]}
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
  end

  # The lines under a group's first line, split at their own indent.
  defp children([_first]), do: []
  defp children([_first | [{_n, indent, _text} | _] = rest]), do: groups(rest, indent)

  defp tokens(lines), do: Enum.flat_map(lines, &line_tokens/1)

  defp line_tokens({n, _indent, text}) do
    case Lexer.tokens(text) do
      {:ok, tokens} -> Enum.map(tokens, &put_elem(&1, 2, n))
      {:error, error} -> throw({:report_error, %{error | line: n}})
    end
  end

  # Clauses

  defp clause([{n, _indent, _text} = first | _] = block, {doc, last}) do
    name =
      case line_tokens(first) do
        [{:word, word, _} | _] -> String.downcase(word)
        _other -> nil
      end

    if name not in @clauses,
      do: fail(n, "Start a clause here: #{Enum.join(@clauses, ", ")}.")

    check_order(name, last, n)
    {read(name, block, doc, n), name}
  end

  defp check_order(name, last, n) do
    cond do
      last == nil and name not in ~w(document form) ->
        fail(
          n,
          "Start with document or form and its name in quotes, such as form 'Task report'."
        )

      last == nil ->
        :ok

      order_of(name) < order_of(last) ->
        fail(n, "Move #{name} before #{last}.")

      order_of(name) == order_of(last) and name not in @repeated ->
        fail(n, "Write #{name} once.")

      true ->
        :ok
    end
  end

  # A form starts where a document does.
  defp order_of("form"), do: order_of("document")
  defp order_of(name), do: Enum.find_index(@clauses, &(&1 == name))

  defp read("document", block, doc, n) do
    case tl(tokens(block)) do
      [{:string, name, _}] -> %{doc | name: name}
      _other -> fail(n, "Write the document's name in quotes after document.")
    end
  end

  defp read("form", block, doc, n) do
    case tl(tokens(block)) do
      [{:string, name, _}] -> %{doc | name: name, kind: :form}
      _other -> fail(n, "Write the form's name in quotes after form.")
    end
  end

  defp read("about", block, doc, n) do
    case tl(tokens(block)) do
      [{:string, about, _}] -> %{doc | about: about}
      _other -> fail(n, "Write one line in quotes after about.")
    end
  end

  # `for member, year`, or a form's `for activity where kind = 'incident'`.
  defp read("for", block, doc, n) do
    {names, where} = starts(tl(tokens(block)), n)
    check_starts(names, where, doc.kind, n)
    %{doc | for: names, where: where}
  end

  defp read("report", [first | rest], doc, n) do
    name =
      case tl(line_tokens(first)) do
        [{:word, name, _}] -> String.downcase(name)
        _other -> fail(n, "Name the report after report, such as report hours.")
      end

    if Enum.any?(doc.reports, &(&1.name == name)),
      do: fail(n, "Give the report another name: #{name} is used twice.")

    if rest == [], do: fail(n, "Write the report's query under report #{name}, indented.")

    case rest |> tokens() |> Parser.parse_tokens() do
      {:ok, query} -> %{doc | reports: [%{name: name, query: query, line: n} | doc.reports]}
      {:error, error} -> throw({:report_error, error})
    end
  end

  defp read("title", block, doc, n) do
    {text, rest} = value(tl(tokens(block)), n)

    {by, rest} =
      case rest do
        [{:word, word, _} | rest] -> if lower(word) == "by", do: value(rest, n), else: {nil, rest}
        rest -> {nil, rest}
      end

    done(rest, "Write the title, then by and who it's by: title 'Letter' by team.legal_name.")
    %{doc | title: %{text: text, by: by, line: n}}
  end

  # `const km_rate = 0.65, 0.67 from 2026-04-15`: a value, and each value after it with
  # the day it starts.
  defp read("const", block, doc, n) do
    case tl(tokens(block)) do
      [{:word, name, _}, {:symbol, "=", _} | [_ | _] = rest] ->
        name = lower(name)

        if Enum.any?(doc.consts, &(&1.name == name)),
          do: fail(n, "Give the const another name: #{name} is used twice.")

        {values, rest} = Parser.list(rest, &const_value(&1, n))
        done(rest, "Put a comma between a const's values, such as 0.65, 0.67 from 2026-04-15.")
        check_from(values, n)
        %{doc | consts: [%{name: name, values: values, line: n} | doc.consts]}

      _other ->
        fail(n, "Write the const's name, =, and its value, such as const meal = 15.00.")
    end
  end

  # `ask name 'Label'`, or `ask each people name 'Label'` for an answer on each row, then
  # remember, default, choose, and hint in any order.
  defp read("ask", block, doc, n) do
    {each, tokens} = ask_each(tl(tokens(block)))

    case tokens do
      [{:word, name, _}, {:string, label, _} | rest] when label != "" ->
        name = lower(name)

        if Enum.any?(doc.asks, &(&1.name == name)),
          do: fail(n, "Give the ask another name: #{name} is used twice.")

        ask = %{name: name, label: label, remember: false, default: nil, choices: []}

        ask =
          ask
          |> Map.merge(%{hint: nil, each: each, line: n})
          |> ask_options(rest, MapSet.new(), n)

        %{doc | asks: [ask | doc.asks]}

      _other ->
        fail(n, "Write the answer's name and its label after ask, such as ask injured 'Injured'.")
    end
  end

  # `compute` and a value a line under it, or `compute each people` and a value for each
  # of a report's rows.
  defp read("compute", [first | _] = block, doc, n) do
    each =
      case tl(line_tokens(first)) do
        [] ->
          nil

        [{:word, word, _}, {:word, report, _}] ->
          if lower(word) == "each", do: lower(report), else: compute_head(n)

        _other ->
          compute_head(n)
      end

    case children(block) do
      [] ->
        fail(n, "Write each value under compute, one a line, such as total = a + b.")

      lines ->
        computes = lines |> Enum.map(&compute(&1, each)) |> Enum.reverse()
        %{doc | computes: computes ++ doc.computes}
    end
  end

  defp read("lock", block, doc, n) do
    case tl(tokens(block)) do
      [{:word, word, _}] -> if lower(word) == "print", do: %{doc | lock: :print}, else: lock(n)
      _other -> lock(n)
    end
  end

  defp read("keep", block, doc, n) do
    case tl(tokens(block)) do
      [] -> fail(n, "Write the values to keep with the PDF after keep, such as keep hours.total.")
      tokens -> %{doc | keep: expressions(tokens, n)}
    end
  end

  defp read("page", block, doc, n) do
    if tl(tokens(block)) != [],
      do: fail(n, "Write page alone: the values print on the form's own page.")

    %{doc | page: true}
  end

  defp read("places", [first | _] = block, doc, n) do
    if tl(line_tokens(first)) != [], do: fail(n, "Write each place on its own line under places.")
    %{doc | places: block |> children() |> Enum.map(&place/1)}
  end

  # `fill` once, and `fill each people into rows` for each rows place: one row a row.
  defp read("fill", [first | _] = block, doc, n) do
    case tl(line_tokens(first)) do
      [] ->
        fill_places(block, doc, n)

      [{:word, each, _}, {:word, report, _}, {:word, into, _}, {:word, place, _}] ->
        if lower(each) != "each" or lower(into) != "into", do: fill_head(n)
        fill_each(block, lower(report), lower(place), doc, n)

      _other ->
        fill_head(n)
    end
  end

  defp read("expect", block, doc, n) do
    {given, rest} =
      case tl(tokens(block)) do
        [{:word, word, _} | rest] = tokens ->
          if lower(word) == "with", do: given(rest, n), else: {[], tokens}

        tokens ->
          {[], tokens}
      end

    {check, rest} = value(rest, n)
    done(rest, "Write one condition after expect, joined with and.")
    %{doc | expects: [%{given: given, check: check, line: n} | doc.expects]}
  end

  defp lock(n), do: fail(n, "Write lock print: the PDF can only be printed.")

  defp finish(%Document{name: nil}), do: fail(nil, "Start with document 'Its name'.")

  defp finish(%Document{kind: :form, for: []}),
    do:
      fail(
        nil,
        "Write for activity after the form's name, such as for activity where kind = 'incident'."
      )

  defp finish(%Document{places: []}),
    do: fail(nil, "Add places: where each value goes on the page.")

  defp finish(%Document{fill: []}), do: fail(nil, "Add fill: what goes in each place.")

  defp finish(doc) do
    {:ok,
     %{
       doc
       | reports: Enum.reverse(doc.reports),
         consts: Enum.reverse(doc.consts),
         asks: Enum.reverse(doc.asks),
         computes: Enum.reverse(doc.computes),
         fill: Enum.reverse(doc.fill),
         expects: Enum.reverse(doc.expects)
     }}
  end

  # Consts

  defp const_value(tokens, n) do
    {value, rest} = literal(tokens, n)

    case rest do
      [{:word, word, _} | after_from] = rest ->
        if lower(word) == "from",
          do: from(value, after_from, n),
          else: {%{value: value, from: nil}, rest}

      rest ->
        {%{value: value, from: nil}, rest}
    end
  end

  defp literal([{:symbol, "-", _}, {:number, number, _} | rest], _n), do: {-number, rest}

  defp literal([{kind, value, _} | rest], _n) when kind in [:number, :string, :date],
    do: {value, rest}

  defp literal(_tokens, n),
    do: fail(n, "Write a const's value as a number, text in quotes, or a date.")

  defp from(value, [{:date, date, _} | rest], _n), do: {%{value: value, from: date}, rest}

  defp from(_value, _tokens, n),
    do: fail(n, "Write the day the value starts after from, such as from 2026-04-15.")

  # The first value holds before any day; each after it starts on a later day.
  defp check_from([%{from: %Date{}} | _], n),
    do: fail(n, "Start with the value before any day, such as 0.65, 0.67 from 2026-04-15.")

  defp check_from([_first | later], n) do
    for %{from: nil} <- later,
        do: fail(n, "Write the day each later value starts, such as 0.67 from 2026-04-15.")

    days = Enum.map(later, & &1.from)

    if Enum.sort(days, Date) != days or Enum.uniq(days) != days,
      do: fail(n, "Write the values in order of the day each starts, earliest first.")

    :ok
  end

  # Computes

  defp compute_head(n),
    do:
      fail(
        n,
        "Write compute alone, or compute each and a report's name, such as compute each people."
      )

  defp compute([{n, _indent, _text} = first | _] = group, each) do
    case line_tokens(first) do
      [{:word, name, _}, {:symbol, "=", _} | _] ->
        [_name, _equals | tokens] = tokens(group)
        if tokens == [], do: fail(n, "Write a value after =.")
        {value, rest} = value(tokens, n)
        done(rest, "Write one value after =.")
        %{name: lower(name), each: each, value: value, line: n}

      _other ->
        fail(n, "Write a name, =, and its value, such as total = subtotal + ohs_total.")
    end
  end

  # Starts

  defp starts(tokens, n) do
    {before, where} =
      Enum.split_while(tokens, fn
        {:word, word, _} -> lower(word) != "where"
        _token -> true
      end)

    names = words(before, n, "Write what the document starts from after for: member, year.")

    case where do
      [] ->
        {names, nil}

      [_where] ->
        fail(n, "Write which activities show the form after where, such as kind = 'incident'.")

      [_where | tokens] ->
        {condition, rest} = Parser.expression(tokens)
        done(rest, "Write one condition after where, joined with and.")
        {names, condition}
    end
  end

  defp check_starts(names, where, kind, n) do
    starts = if kind == :form, do: ["activity"], else: @starts

    for name <- names, name not in starts, do: fail(n, not_a_start(kind, name))

    if where != nil and names != ["activity"],
      do: fail(n, "Take out where: it says which activities show a form.")

    case names -- Enum.uniq(names) do
      [] -> :ok
      [name | _] -> fail(n, "Write #{name} once after for.")
    end
  end

  defp not_a_start(:form, _name),
    do: "A form starts from an activity: for activity where kind = 'incident'."

  defp not_a_start(_kind, "activity"),
    do: "Start with form 'Its name': what starts from an activity is a form."

  defp not_a_start(_kind, name),
    do: "A document starts from #{Enum.join(@starts, " or ")}, not #{name}."

  # Asks

  # `each people` before an ask's name: the report it asks on each row of.
  defp ask_each([{:word, word, _}, {:word, report, _}, {:word, _, _} | _] = tokens) do
    if lower(word) == "each", do: {lower(report), Enum.drop(tokens, 2)}, else: {nil, tokens}
  end

  defp ask_each(tokens), do: {nil, tokens}

  defp ask_options(ask, [], _seen, _n), do: ask

  defp ask_options(ask, [{:word, word, _} | rest], seen, n) do
    option = lower(word)

    if option not in @ask_options,
      do: fail(n, "Remove #{word}: an ask takes #{Enum.join(@ask_options, ", ")}.")

    if MapSet.member?(seen, option), do: fail(n, "Write #{option} once.")
    {ask, rest} = ask_option(option, ask, rest, n)
    ask_options(ask, rest, MapSet.put(seen, option), n)
  end

  defp ask_options(_ask, [token | _], _seen, _n),
    do:
      fail(
        elem(token, 2),
        "Write the ask's options after its label: remember, default, choose, or hint."
      )

  defp ask_option("remember", ask, rest, _n), do: {%{ask | remember: true}, rest}

  defp ask_option("default", ask, rest, n) do
    if rest == [], do: fail(n, "Write a value after default, such as default 0.")
    {value, rest} = value(rest, n)
    {%{ask | default: value}, rest}
  end

  defp ask_option("choose", ask, rest, n) do
    message = "Write the answers in quotes after choose, such as choose 'Yes', 'No'."

    {choices, rest} =
      Parser.list(rest, fn
        [{:string, choice, _} | rest] -> {choice, rest}
        _tokens -> fail(n, message)
      end)

    {%{ask | choices: choices}, rest}
  end

  defp ask_option("hint", ask, [{:string, hint, _} | rest], _n), do: {%{ask | hint: hint}, rest}
  defp ask_option("hint", _ask, _rest, n), do: fail(n, "Write the hint in quotes after hint.")

  # `with a = 1, b = 'x':`, each a name and a value, and a report's row as its name and
  # each of its values: `people hours 6, km 30`. Commas between them are optional.
  defp given(tokens, n), do: given(tokens, [], n)

  defp given([{:symbol, ":", _} | rest], [_ | _] = items, _n), do: {Enum.reverse(items), rest}
  defp given([{:symbol, ",", _} | rest], [_ | _] = items, n), do: given(rest, items, n)

  defp given([{:word, report, line}, {:word, _, _} | _] = tokens, items, n) do
    if lower(report) in ~w(and or not),
      do: fail(n, "Give a name a value after with, such as hours.total = 90.")

    {pairs, rest} = row_values(tl(tokens), [], n)
    given(rest, [{:row, lower(report), pairs, line} | items], n)
  end

  defp given([], _items, n),
    do: fail(n, "Write a colon after the values, then what to expect: with :year = 2025: …")

  defp given(tokens, items, n) do
    {expr, rest} = Parser.expression(tokens)
    given(rest, [given_item(expr) | items], n)
  end

  # A row's values, each a name and then a value with no =, such as hours 6. A comma
  # followed by anything else ends the row.
  defp row_values([{:word, name, line} | rest], pairs, n) do
    {value, rest} =
      case Parser.expression(rest) do
        {{:literal, value, _}, rest} -> {value, rest}
        _other -> fail(n, "Give each of a row's values after its name, such as people hours 6.")
      end

    pairs = [{lower(name), value, line} | pairs]

    case rest do
      [{:symbol, ",", _}, {:word, _, _}, next | _] = rest ->
        if value_start?(next),
          do: row_values(tl(rest), pairs, n),
          else: {Enum.reverse(pairs), rest}

      rest ->
        {Enum.reverse(pairs), rest}
    end
  end

  defp row_values(_tokens, _pairs, n),
    do: fail(n, "Give each of a row's values after its name, such as people hours 6.")

  defp value_start?({kind, _value, _line}) when kind in [:number, :string, :date], do: true
  defp value_start?({:symbol, "-", _line}), do: true
  defp value_start?({:word, word, _line}), do: lower(word) in ~w(true false null)
  defp value_start?(_token), do: false

  defp given_item({:op, :eq, {kind, _, _, _} = target, {:literal, value, _}, line})
       when kind == :field,
       do: {target, value, line}

  defp given_item({:op, :eq, {:value, _, _} = target, {:literal, value, _}, line}),
    do: {target, value, line}

  # `today`, the report language's TODAY.
  defp given_item({:op, :eq, {:range, "TODAY", nil, _} = target, {:literal, value, _}, line}),
    do: {target, value, line}

  defp given_item(expr),
    do:
      fail(
        Query.line(expr),
        "Give a name a value after with, such as hours.total = 90, not #{Query.text(expr)}."
      )

  # Places

  # A rows place's own options are on its first line, and its row's places under it.
  defp place([{n, _indent, _text} = first | _] = group) do
    case line_tokens(first) do
      [{:word, name, _}, {:word, kind, _} | rest] ->
        if lower(kind) == "rows",
          do: rows_place(lower(name), rest, group, n),
          else: place(group, n)

      _other ->
        place(group, n)
    end
  end

  defp place(group, n) do
    case tokens(group) do
      [{:word, name, _}, {:word, kind, _} | rest] ->
        kind = lower(kind)

        if not Map.has_key?(@kinds, kind),
          do: fail(n, "Write text, image, flow, or tick after #{name}, not #{kind}.")

        %{name: lower(name), kind: Map.fetch!(@kinds, kind), line: n}
        |> Map.merge(%{across: false, level_with: nil, fit: false, page: 1})
        |> place_options(rest, n)

      _other ->
        fail(n, "Write the place's name and kind, such as total text top 2in, left 1in.")
    end
  end

  defp rows_place(name, options, group, n) do
    places =
      case children(group) do
        [] -> fail(n, "Write the places in each row under #{name}, indented.")
        groups -> Enum.map(groups, &place/1)
      end

    %{name: name, kind: :rows, line: n, places: places}
    |> Map.merge(%{across: false, level_with: nil, fit: false, page: 1})
    |> place_options(options, n)
  end

  defp place_options(place, [], _n), do: place

  defp place_options(place, tokens, n) do
    {place, rest} = place_option(place, tokens, n)

    case rest do
      [] -> place
      [{:symbol, ",", _} | rest] -> place_options(place, rest, n)
      _rest -> fail(n, "Put a comma between a place's options.")
    end
  end

  defp place_option(place, [{:word, word, _} | rest], n) do
    case lower(word) do
      "across" ->
        {%{place | across: true}, rest}

      "down" ->
        {place, rest}

      "fit" ->
        {%{place | fit: true}, rest}

      word when word in ~w(level page align lines) ->
        valued_option(word, place, rest, n)

      name when name in @lengths ->
        length_option(place, name, rest, n)

      other ->
        fail(
          n,
          "Remove #{other}: a place takes #{Enum.join(@lengths, ", ")}, lines, across, fit, align, page, and level with."
        )
    end
  end

  defp place_option(_place, _tokens, n), do: fail(n, "Write a place's options, such as top 1in.")

  # An option and what follows it: `level with letter`, `page 2`, `align right`, `lines 8`.
  defp valued_option("level", place, rest, n), do: level_with(place, rest, n)
  defp valued_option("page", place, rest, n), do: page_option(place, rest, n)
  defp valued_option("align", place, rest, n), do: align_option(place, rest, n)
  defp valued_option("lines", place, rest, n), do: lines_option(place, rest, n)

  # Which page of the form's page it's on, from 1.
  defp page_option(place, [{:number, page, _} | rest], _n) when is_integer(page) and page > 0,
    do: {%{place | page: page}, rest}

  defp page_option(_place, _tokens, n),
    do: fail(n, "Write which page after page, such as page 2.")

  # `align right` puts each line against the place's right edge, as a column of money.
  defp align_option(place, [{:word, word, _} | rest], n) do
    case Map.fetch(@aligns, lower(word)) do
      {:ok, align} -> {Map.put(place, :align, align), rest}
      :error -> align_option(place, [], n)
    end
  end

  defp align_option(_place, _tokens, n),
    do: fail(n, "Write left, right, or center after align, such as align right.")

  # At most how many of the page's lines a text wraps on, from 1.
  defp lines_option(place, [{:number, lines, _} | rest], n)
       when is_integer(lines) and lines > 0 do
    if Map.has_key?(place, :lines), do: fail(n, "Write lines once.")
    {Map.put(place, :lines, lines), rest}
  end

  defp lines_option(_place, _tokens, n),
    do: fail(n, "Write how many lines after lines, such as lines 8.")

  defp level_with(place, [{:word, word, _}, {:word, other, _} | rest], n) do
    if lower(word) != "with", do: fail(n, "Write level with and a flow's name.")
    {%{place | level_with: lower(other)}, rest}
  end

  defp level_with(_place, _tokens, n), do: fail(n, "Write level with and a flow's name.")

  defp length_option(place, name, tokens, n) do
    key = Map.fetch!(@atoms, name)
    if Map.has_key?(place, key), do: fail(n, "Write #{name} once.")
    {points, rest} = length(tokens, name, n)
    {Map.put(place, key, points), rest}
  end

  # A length in points: `1in`, `12pt`, or `20mm`.
  defp length([{:number, number, _}, {:word, unit, _} | rest], name, n) do
    case Map.fetch(@units, lower(unit)) do
      {:ok, points} -> {number * points, rest}
      :error -> fail(n, "Write #{name} in in, pt, or mm, such as #{name} 1in.")
    end
  end

  defp length(_tokens, name, n),
    do: fail(n, "Write #{name} in in, pt, or mm, such as #{name} 1in.")

  # Fill

  defp fill_head(n),
    do:
      fail(
        n,
        "Write fill alone, or fill each, a report, into, and a rows place: fill each people into rows."
      )

  # Fills are kept newest first until `finish/1`, as the other repeated clauses are.
  defp fill_places(block, doc, n) do
    if Enum.any?(doc.fill, &(not match?({:each, _, _}, &1.value))),
      do: fail(n, "Write fill once.")

    fills = block |> children() |> Enum.map(&fill(&1, doc.places))
    %{doc | fill: Enum.reverse(fills, doc.fill)}
  end

  defp fill_each(block, report, place, doc, n) do
    if Enum.any?(doc.fill, &(&1.place == place)), do: fail(n, "Fill #{place} once.")

    case children(block) do
      [] ->
        fail(n, "Write what goes in each of a row's places under fill each, one a line.")

      lines ->
        fills = Enum.map(lines, &fill(&1, []))
        %{doc | fill: [%{place: place, value: {:each, report, fills}, line: n} | doc.fill]}
    end
  end

  defp fill([{n, _indent, _text} = first | _] = group, places) do
    case line_tokens(first) do
      [{:word, name, _}, {:symbol, "=", _} | inline] ->
        name = lower(name)
        flow? = Enum.any?(places, &(&1.name == name and &1.kind == :flow))
        %{place: name, value: fill_value(flow?, inline, group, n), line: n}

      _other ->
        fail(n, "Write a place's name, =, and its value, such as total = hours.total.")
    end
  end

  defp fill_value(false, _inline, group, n) do
    [_name, _equals | tokens] = tokens(group)
    if tokens == [], do: fail(n, "Write a value after =.")
    {value, rest} = value(tokens, n)
    done(rest, "Write one value after =.")
    value
  end

  # A flow's items: in a list after =, or one a line under it.
  defp fill_value(true, [], group, n) do
    case children(group) do
      [] -> fail(n, "Write the flow's items under it, one a line, indented.")
      items -> {:flow, Enum.map(items, &item/1)}
    end
  end

  defp fill_value(true, _inline, group, n) do
    [_name, _equals | tokens] = tokens(group)
    {items, rest} = Parser.list(tokens, &item_tokens(&1, n))
    done(rest, "Put a comma between a flow's items.")
    {:flow, items}
  end

  defp item([{n, _indent, _text} | _] = group) do
    {item, rest} = item_tokens(tokens(group), n)
    done(rest, "Write one item a line in a flow.")
    item
  end

  defp item_tokens([{:word, word, line} | rest] = tokens, n) do
    case lower(word) do
      "space" -> space(rest, line)
      "image" -> image(rest, line, n)
      _other -> value(tokens, n)
    end
  end

  defp item_tokens(tokens, n), do: value(tokens, n)

  defp space([{:number, count, _} | rest], line) when is_integer(count) and count > 0,
    do: space_if(count, rest, line)

  defp space(rest, line), do: space_if(1, rest, line)

  defp space_if(count, rest, line) do
    {condition, rest} = postfix_if(rest)
    {{:space, count, condition, line}, rest}
  end

  defp image(tokens, line, n) do
    {expr, rest} = Parser.expression(tokens)
    {options, rest} = image_options(rest, %{}, n)
    {condition, rest} = postfix_if(rest)
    {{:image, strings(expr, n), options, condition, line}, rest}
  end

  defp image_options([{:word, word, _} | rest] = tokens, options, n) do
    name = lower(word)

    if name in @image_options do
      {points, rest} = length(rest, name, n)
      image_options(rest, Map.put(options, Map.fetch!(@atoms, name), points), n)
    else
      {options, tokens}
    end
  end

  defp image_options(tokens, options, _n), do: {options, tokens}

  # Values

  # `if c then a else b`, or an expression, `as format`, then `if condition`.
  defp value([{:word, word, line} | rest] = tokens, n) do
    if lower(word) == "if" do
      {condition, rest} = Parser.expression(rest)
      rest = keyword(rest, "then", line, "Write then after if's condition.")
      {yes, rest} = formatted(rest, n)
      rest = keyword(rest, "else", line, "Write else and a value after then's.")
      {no, rest} = formatted(rest, n)
      {{:if, strings(condition, n), yes, no, line}, rest}
    else
      plain_value(tokens, n)
    end
  end

  defp value(tokens, n), do: plain_value(tokens, n)

  defp plain_value(tokens, n) do
    {value, rest} = formatted(tokens, n)

    case postfix_if(rest) do
      {nil, rest} -> {value, rest}
      {condition, rest} -> {{:when, value, condition, Query.line(value)}, rest}
    end
  end

  defp formatted([], n), do: fail(n, "Write a value here.")

  defp formatted(tokens, n) do
    {expr, rest} = Parser.expression(tokens)
    {expr, rest} = on(strings(expr, n), rest, n)

    case rest do
      [{:word, as, _}, {:word, format, _} | after_format] ->
        if lower(as) == "as",
          do: {{:as, expr, lower(format), Query.line(expr)}, after_format},
          else: {expr, rest}

      rest ->
        {expr, rest}
    end
  end

  # `km_rate on started_at`: a const's value on a day.
  defp on(expr, [{:word, word, line} | rest] = tokens, n) do
    if lower(word) == "on" do
      {day, rest} = Parser.expression(rest)
      {{:on, expr, strings(day, n), line}, rest}
    else
      {expr, tokens}
    end
  end

  defp on(expr, tokens, _n), do: {expr, tokens}

  defp postfix_if([{:word, word, _} | rest] = tokens) do
    if lower(word) == "if" do
      {condition, rest} = Parser.expression(rest)
      {condition, rest}
    else
      {nil, tokens}
    end
  end

  defp postfix_if(tokens), do: {nil, tokens}

  # Text with `{value}` in it is a `{:text, parts, line}`: each part a string, or
  # `{expr, format}` with format nil when it has none.
  defp strings({:literal, text, line}, _n) when is_binary(text) do
    if String.contains?(text, ["{", "}"]),
      do: {:text, text_parts(text, line), line},
      else: {:literal, text, line}
  end

  defp strings(expr, n) when is_tuple(expr) do
    expr
    |> Tuple.to_list()
    |> Enum.map(fn
      part when is_tuple(part) ->
        strings(part, n)

      parts when is_list(parts) ->
        Enum.map(parts, &if(is_tuple(&1), do: strings(&1, n), else: &1))

      other ->
        other
    end)
    |> List.to_tuple()
  end

  defp text_parts(text, line) do
    ~r/\{([^{}]*)\}/
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(&text_part(&1, line))
  end

  defp text_part(part, line) do
    case Regex.run(~r/\A\{([^{}]*)\}\z/, part) do
      [_all, inner] ->
        interpolation(inner, line)

      nil ->
        if String.contains?(part, ["{", "}"]),
          do: fail(line, "Close each { with }: text puts a value between them.")

        part
    end
  end

  defp interpolation(inner, line) do
    tokens = line_tokens({line, 0, inner})
    if tokens == [], do: fail(line, "Write a value between { and }.")
    {expr, rest} = formatted(tokens, line)
    done(rest, "Write one value between { and }, such as {hours.total as duration}.")

    case expr do
      {:as, expr, format, _line} -> {expr, format}
      expr -> {expr, nil}
    end
  end

  # Helpers

  defp expressions(tokens, n) do
    {items, rest} = Parser.list(tokens, &Parser.expression/1)
    done(rest, "Put a comma between the values.")
    Enum.map(items, &strings(&1, n))
  end

  defp words(tokens, n, message) do
    {items, rest} =
      Parser.list(tokens, fn
        [{:word, word, _} | rest] -> {lower(word), rest}
        _tokens -> fail(n, message)
      end)

    done(rest, message)
    items
  end

  defp keyword([{:word, word, _} | rest], keyword, line, message) do
    if lower(word) == keyword, do: rest, else: fail(line, message)
  end

  defp keyword(_tokens, _keyword, line, message), do: fail(line, message)

  defp done([], _message), do: :ok
  defp done([token | _], message), do: fail(elem(token, 2), message)

  defp lower(word), do: String.downcase(word)

  defp fail(line, message), do: throw({:report_error, Error.new(line, message)})
end
