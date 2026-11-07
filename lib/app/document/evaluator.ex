defmodule App.Document.Evaluator do
  @moduledoc """
  Works out what a checked App.Document prints (#918), from a map of the values it reads.
  Pure: the caller runs the reports and loads the pictures.

  A blank value is nil or text with nothing in it: `is null` is true for it, `coalesce`
  skips it, and a flow leaves it out. Text compares exactly, case and all, since an
  `expect` checks what a page prints. A picture stays whatever the caller gave, and
  `qr(link)` is `{:qr, link}` for the printer to draw.

  A form's answer is `:name` in the values. One not given, or blank, takes its default,
  in the order the asks are written, so a default can read an answer above it. A tick
  is true or false.

  A form's arithmetic is in exact decimals (#950): each number becomes a Decimal, so
  0.67 × 30 is 20.10, never 20.099999. A blank counts as 0, as a spreadsheet's empty
  cell does, and dividing by 0 is blank. A report with a row each is a list in the
  values, `%{key, values}` for each row, where `key` is the row's member or item
  (`"member:12"`) and an answer for it is `{name, key}` in the values. Each compute is
  worked out in order: one for each row in its row, the rest once. A value already
  given, as an expect gives one, is kept.

  A form's rows place prints a row for each of a report's rows, `lines` to a copy of its
  page, and the rest on more copies. Each place prints on each copy, reading `page` and
  `pages`, and the copy's rows as the rows place's name, so `sum(rows.total)` is that
  copy's subtotal. A row's places are named for the row, `rows.19.who`.
  """

  alias App.Document
  alias App.Report.Error
  alias App.Report.Query
  alias Service.Format

  @doc "A select item's name in a document: `member.name`, in lower case."
  def name(ast) do
    ast
    |> Query.text()
    |> String.split(".")
    |> Enum.map_join(".", fn
      "`" <> _ = title -> title
      name -> String.downcase(name)
    end)
  end

  @doc "What the document prints from `values`. See App.Document.evaluate/3."
  def evaluate(%Document{} = doc, values, timezone),
    do: doc |> prepare(values, timezone) |> output(doc)

  @doc "The values worked out, with what reads them. See App.Document.values/3."
  def prepare(%Document{} = doc, values, timezone) do
    %{values: values, timezone: timezone, row: nil, consts: consts(doc)}
    |> defaults(doc.asks)
    |> rows(doc)
    |> computes(doc.computes)
  end

  defp consts(doc), do: Map.new(doc.consts, &{&1.name, &1.values})

  defp defaults(env, asks),
    do: asks |> Enum.filter(&is_nil(&1.each)) |> Enum.reduce(env, &default/2)

  defp rows(env, doc), do: Enum.reduce(doc.reports, env, &answer_rows(&1, doc.asks, &2))

  defp computes(env, computes),
    do: computes |> Enum.chunk_by(& &1.each) |> Enum.reduce(env, &compute/2)

  defp output(env, doc) do
    title = doc.title
    copies = copies(doc, env)

    %{
      title: title && text_value(title.text, env),
      author: title && title.by && text_value(title.by, env),
      lock: doc.lock,
      keep: Map.new(doc.keep, &{name(&1), value(&1, env)}),
      page: doc.page,
      copies: length(copies),
      places:
        copies
        |> Enum.with_index(1)
        |> Enum.flat_map(&copy_places(&1, length(copies), doc, env))
    }
  end

  # A rows place's rows, `lines` to a copy of the form's page; one copy with none.
  defp copies(doc, env) do
    with %{lines: lines} = rows <- Enum.find(doc.places, &(&1.kind == :rows)),
         %{value: {:each, report, _fills}} <- Enum.find(doc.fill, &(&1.place == rows.name)),
         [_ | _] = all <- env.values |> Map.get(report, []) |> Enum.with_index() do
      Enum.chunk_every(all, lines)
    else
      _none -> [[]]
    end
  end

  # Each place on one copy, which reads `page` and `pages`, and the rows on it as the
  # rows place's name. A rows place is a text or tick for each place in each row.
  defp copy_places({rows, copy}, pages, doc, env) do
    env = copy_env(env, doc, rows, copy, pages)

    Enum.flat_map(doc.places, fn
      %{kind: :rows} = place ->
        %{value: {:each, _report, fills}} = Enum.find(doc.fill, &(&1.place == place.name))
        rows |> Enum.with_index() |> Enum.flat_map(&row_places(&1, place, fills, copy, env))

      place ->
        [place |> place(doc.fill, env) |> Map.put(:copy, copy)]
    end)
  end

  defp copy_env(env, doc, rows, copy, pages) do
    values =
      env.values
      |> Map.merge(%{"page" => copy, "pages" => pages})
      |> put_copy_rows(doc, Enum.map(rows, &elem(&1, 0)))

    %{env | values: values}
  end

  defp put_copy_rows(values, doc, rows) do
    case Enum.find(doc.places, &(&1.kind == :rows)) do
      nil -> values
      place -> Map.put(values, place.name, rows)
    end
  end

  # A row's places, each `top` below the row's own top, named for the row: `rows.3.km`.
  defp row_places({{row, n}, i}, rows, fills, copy, env) do
    top = rows.top + i * rows.pitch
    env = %{env | row: row.values}

    for place <- rows.places do
      %{value: value} = Enum.find(fills, &(&1.place == place.name))

      place
      |> Map.merge(%{
        name: "#{rows.name}.#{n + 1}.#{place.name}",
        top: top + Map.get(place, :top, 0),
        page: rows.page,
        copy: copy,
        row: n + 1
      })
      |> Map.put(:value, place_value(place, value, env))
    end
  end

  defp default(%{default: nil}, env), do: env

  defp default(ask, env) do
    key = ":#{ask.name}"

    if blank?(Map.get(env.values, key)),
      do: %{env | values: Map.put(env.values, key, value(ask.default, env))},
      else: env
  end

  # Each row's answers: one given in the row, then one kept for the row's member or
  # item, then the default, worked out in the row.
  defp answer_rows(%{rows: true, name: report}, asks, env) do
    asks = Enum.filter(asks, &(&1.each == report))
    rows = env.values |> Map.get(report, []) |> Enum.map(&answer_row(&1, asks, env))
    %{env | values: Map.put(env.values, report, rows)}
  end

  defp answer_rows(_report, _asks, env), do: env

  defp answer_row(row, asks, env) do
    Enum.reduce(asks, row, fn ask, row ->
      given = Map.get(row.values, ask.name)
      kept = row.key && Map.get(env.values, {ask.name, row.key})

      answer =
        cond do
          not blank?(given) -> given
          not blank?(kept) -> kept
          ask.default -> value(ask.default, %{env | row: row.values})
          true -> nil
        end

      %{row | values: Map.put(row.values, ask.name, answer)}
    end)
  end

  defp compute([%{each: nil} | _] = computes, env) do
    Enum.reduce(computes, env, fn compute, env ->
      if Map.has_key?(env.values, compute.name),
        do: env,
        else: %{env | values: Map.put(env.values, compute.name, value(compute.value, env))}
    end)
  end

  defp compute([%{each: report} | _] = computes, env) do
    rows =
      env.values
      |> Map.get(report, [])
      |> Enum.map(fn row ->
        %{row | values: Enum.reduce(computes, row.values, &compute_in_row(&1, &2, env))}
      end)

    %{env | values: Map.put(env.values, report, rows)}
  end

  defp compute_in_row(compute, values, env) do
    if Map.has_key?(values, compute.name),
      do: values,
      else: Map.put(values, compute.name, value(compute.value, %{env | row: values}))
  end

  defp place(place, fill, env) do
    %{value: value} = Enum.find(fill, &(&1.place == place.name))
    Map.put(place, :value, place_value(place, value, env))
  end

  defp place_value(%{kind: :flow, across: across?}, {:flow, items}, env),
    do: items |> Enum.map(&item(&1, across?, env)) |> Enum.reject(&is_nil/1)

  defp place_value(%{kind: :tick}, value, env), do: holds?(value, env)
  defp place_value(%{kind: :image}, value, env), do: value(value, env)
  defp place_value(%{kind: :text}, value, env), do: text_value(value, env)

  defp item({:space, count, condition, _line}, _across?, env),
    do: if(holds?(condition, env), do: {:space, count})

  defp item({:image, expr, options, condition, _line}, _across?, env) do
    image = value(expr, env)
    if holds?(condition, env) and not blank?(image), do: {:image, image, options}
  end

  # Across, each item is a picture; down, text.
  defp item(expr, true, env) do
    image = value(expr, env)
    if not blank?(image), do: {:image, image, %{}}
  end

  defp item(expr, false, env) do
    value = value(expr, env)
    if not blank?(value), do: {:text, to_text(value)}
  end

  defp holds?(nil, _env), do: true
  defp holds?(condition, env), do: value(condition, env) == true

  @doc "A value as text, in `format` when it has one, as a place prints it."
  def printed(value, nil, _timezone), do: to_text(value)
  def printed(value, format, timezone), do: value |> format(format, timezone) |> to_text()

  @doc """
  A place's text: a text place's value, or a flow's lines with a blank line for each
  space and nothing for a picture. Nil for an image, or a flow across.
  """
  def text(output, place_name) do
    case Enum.find(output.places, &(&1.name == place_name)) do
      %{kind: :text, value: value} -> value
      %{kind: :flow, across: false, value: items} -> flow_text(items)
      _other -> nil
    end
  end

  defp flow_text(items) do
    items
    |> Enum.flat_map(fn
      {:text, text} -> String.split(text, ~r/\r?\n/)
      {:space, count} -> List.duplicate("", count)
      {:image, _image, _options} -> []
    end)
    |> Enum.join("\n")
  end

  @doc "`:ok` when each `expect` holds, or `{:error, [%Error{}]}` naming those that don't."
  def expect(%Document{} = doc) do
    failed =
      for expect <- doc.expects,
          env = prepare(doc, given(expect.given), "Etc/UTC"),
          read = read(env, output(env, doc), expect.given),
          not holds?(expect.check, read) do
        Error.new(expect.line, "This expect fails: #{described(expect.check, read)}")
      end

    if failed == [], do: :ok, else: {:error, failed}
  end

  # What an expect gives, as values: a row is one of its report's rows, in order.
  defp given(given), do: given |> Enum.reverse() |> Enum.reduce(%{}, &give/2)

  defp give({:row, report, values, _line}, given) do
    row = %{key: nil, values: Map.new(values, fn {name, value, _line} -> {name, value} end)}
    Map.update(given, report, [row], &[row | &1])
  end

  defp give({{:value, name, _}, value, _line}, given), do: Map.put(given, ":#{name}", value)

  defp give({{:field, _path, [], _} = field, value, _line}, given),
    do: Map.put(given, name(field), value)

  defp give({{:range, "TODAY", nil, _}, value, _line}, given), do: Map.put(given, "today", value)

  # The values, with each place's text and the title, as an expect reads them. A tick
  # reads as whether it's ticked. An expect that gives one row reads that row first.
  defp read(env, output, given) do
    places =
      output.places
      |> Enum.filter(&(Map.get(&1, :copy, 1) == 1 and not Map.has_key?(&1, :row)))
      |> Map.new(fn
        %{kind: :tick} = place -> {place.name, place.value}
        place -> {place.name, text(output, place.name)}
      end)
      |> Map.merge(%{"title" => output.title, "author" => output.author})

    row =
      case for({:row, report, _values, _line} <- given, do: report) do
        [report] -> env.values |> Map.fetch!(report) |> hd() |> Map.fetch!(:values)
        _none_or_more -> nil
      end

    %{env | values: Map.merge(env.values, places), row: row}
  end

  # The condition, and what each value it reads holds.
  defp described(check, env) do
    names = check |> names() |> Enum.uniq()

    shown =
      for name <- names,
          {:ok, value} <- [read_name(name, env)] do
        "#{name} is #{inspect(value, printable_limit: 2000)}"
      end

    Enum.join(["#{safe_text(check)}." | shown], " ")
  end

  defp read_name(name, %{row: row, values: values}) do
    if row && Map.has_key?(row, name), do: {:ok, row[name]}, else: Map.fetch(values, name)
  end

  defp names({:field, path, [], _line} = field) when is_list(path), do: [name(field)]
  defp names(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> names()
  defp names(list) when is_list(list), do: Enum.flat_map(list, &names/1)
  defp names(_other), do: []

  defp safe_text(expr) do
    Query.text(expr)
  rescue
    FunctionClauseError -> "the condition"
  end

  # Values

  defp text_value(expr, env) do
    value = value(expr, env)
    if not blank?(value), do: to_text(value)
  end

  @doc false
  def value({:literal, value, _line}, _env), do: value

  def value({:field, [function], args, _line}, env) when args != [],
    do: function(String.downcase(function), args, env)

  # A row's value first, then the document's, then a const's.
  def value({:field, _path, [], _line} = field, env) do
    key = name(field)

    cond do
      env.row && Map.has_key?(env.row, key) -> env.row[key]
      Map.has_key?(env.values, key) -> env.values[key]
      true -> const(key, nil, env)
    end
  end

  def value({:on, {:field, [name], [], _}, day, _line}, env) do
    key = String.downcase(name)

    if Map.has_key?(env.values, key),
      do: env.values[key],
      else: const(key, day(value(day, env), env.timezone), env)
  end

  def value({:arith, op, left, right, _line}, env),
    do: arith(op, decimal(value(left, env)), decimal(value(right, env)))

  def value({:call, "min", false, args, _line}, env),
    do: args |> Enum.map(&decimal(value(&1, env))) |> Enum.min(Decimal)

  def value({:call, "max", false, args, _line}, env),
    do: args |> Enum.map(&decimal(value(&1, env))) |> Enum.max(Decimal)

  # `sum(people.total)`: the column over the report's rows, 0 for none.
  def value({:call, "sum", false, [{:field, [report | path], [], line}], _line}, env) do
    key = name({:field, path, [], line})

    env.values
    |> Map.get(String.downcase(report), [])
    |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, decimal(Map.get(&1.values, key))))
  end

  def value({:value, name, _line}, env), do: Map.get(env.values, ":#{name}")
  def value({:range, "TODAY", nil, _line}, env), do: Map.get(env.values, "today")

  def value({:text, parts, _line}, env) do
    Enum.map_join(parts, fn
      part when is_binary(part) -> part
      {expr, nil} -> expr |> value(env) |> to_text()
      {expr, format} -> expr |> value(env) |> format(format, env.timezone) |> to_text()
    end)
  end

  def value({:as, expr, format, _line}, env),
    do: expr |> value(env) |> format(format, env.timezone)

  def value({:when, value, condition, _line}, env),
    do: if(holds?(condition, env), do: value(value, env))

  def value({:if, condition, yes, no, _line}, env),
    do: if(holds?(condition, env), do: value(yes, env), else: value(no, env))

  def value({:op, :and, left, right, _line}, env), do: holds?(left, env) and holds?(right, env)
  def value({:op, :or, left, right, _line}, env), do: holds?(left, env) or holds?(right, env)
  def value({:not, expr, _line}, env), do: not holds?(expr, env)

  def value({:is_null, expr, negated?, _line}, env), do: blank?(value(expr, env)) != negated?

  def value({:in, expr, items, negated?, _line}, env) do
    left = value(expr, env)
    found = Enum.any?(items, &same?(left, value(&1, env)))
    not blank?(left) and found != negated?
  end

  def value({:op, op, left, right, _line}, env),
    do: compare(op, value(left, env), value(right, env))

  defp function("coalesce", args, env),
    do: args |> Enum.map(&value(&1, env)) |> Enum.find(&(not blank?(&1)))

  defp function("qr", [link], env), do: link |> value(env) |> qr()

  defp function("floor", [n], env),
    do: n |> value(env) |> decimal() |> Decimal.round(0, :floor)

  defp function("round", args, env), do: round(args, env)
  defp function("days", [hours], env), do: hours |> value(env) |> decimal() |> days()

  defp function("hours", args, env),
    do: args |> Enum.map(&value(&1, env)) |> hours(env.timezone)

  defp qr(link), do: if(blank?(link), do: nil, else: {:qr, link})

  # Arithmetic

  defp arith(:add, a, b), do: Decimal.add(a, b)
  defp arith(:sub, a, b), do: Decimal.sub(a, b)
  defp arith(:mul, a, b), do: Decimal.mult(a, b)
  defp arith(:div, a, b), do: if(Decimal.eq?(b, 0), do: nil, else: Decimal.div(a, b))

  # A number as an exact decimal: 0.67 is 0.67, as written. A blank is 0.
  defp decimal(%Decimal{} = n), do: n
  defp decimal(n) when is_integer(n), do: Decimal.new(n)
  defp decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp decimal(nil), do: Decimal.new(0)
  defp decimal(""), do: Decimal.new(0)

  defp round([value], env), do: value |> value(env) |> decimal() |> Decimal.round(0, :half_up)

  defp round([value, {:literal, places, _line}], env),
    do: value |> value(env) |> decimal() |> Decimal.round(places, :half_up)

  # The days that many hours start: 6 hours is 1 day, and 25 hours is 2.
  defp days(hours), do: hours |> Decimal.div(24) |> Decimal.round(0, :ceiling) |> Decimal.max(0)

  # The hours between two times, or a duration's hours: it's kept in minutes.
  defp hours([from, to], timezone) do
    if blank?(from) or blank?(to) do
      nil
    else
      to
      |> moment(timezone)
      |> DateTime.diff(moment(from, timezone))
      |> Decimal.div(3600)
    end
  end

  defp hours([minutes], _timezone) do
    if blank?(minutes), do: nil, else: minutes |> decimal() |> Decimal.div(60)
  end

  defp moment(%DateTime{} = at, _timezone), do: at
  defp moment(%Date{} = day, timezone), do: DateTime.new!(day, ~T[00:00:00], timezone)

  # A const's value on `day`: the last that starts by then. A const that changes has no
  # value on a blank day.
  defp const(name, day, env) do
    case Map.get(env.consts, name) do
      nil ->
        nil

      [%{value: value}] ->
        value

      [_first | _later] when is_nil(day) ->
        nil

      [first | later] ->
        Enum.reduce(later, first, &if(Date.after?(&1.from, day), do: &2, else: &1)).value
    end
  end

  defp day(%DateTime{} = at, timezone),
    do: at |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

  defp day(%Date{} = day, _timezone), do: day
  defp day(_blank, _timezone), do: nil

  # As SQL does, a blank compares with nothing. Numbers compare as numbers, exactly.
  defp compare(op, left, right) do
    cond do
      blank?(left) or blank?(right) ->
        false

      op in [:contains, :starts_with, :ends_with] ->
        match(op, to_text(left), to_text(right))

      number?(left) and number?(right) ->
        numbers(op, left |> decimal() |> Decimal.compare(decimal(right)))

      op == :eq ->
        same?(left, right)

      op == :ne ->
        not same?(left, right)

      true ->
        order(op, sort_key(left), sort_key(right))
    end
  end

  defp number?(value), do: is_number(value) or is_struct(value, Decimal)

  defp numbers(:eq, order), do: order == :eq
  defp numbers(:ne, order), do: order != :eq
  defp numbers(:lt, order), do: order == :lt
  defp numbers(:gt, order), do: order == :gt
  defp numbers(:le, order), do: order != :gt
  defp numbers(:ge, order), do: order != :lt

  defp same?(a, b) do
    if number?(a) and number?(b), do: a |> decimal() |> Decimal.eq?(decimal(b)), else: a == b
  end

  defp match(:contains, text, part), do: String.contains?(text, part)
  defp match(:starts_with, text, part), do: String.starts_with?(text, part)
  defp match(:ends_with, text, part), do: String.ends_with?(text, part)

  defp sort_key(%Date{} = date), do: Date.to_gregorian_days(date)
  defp sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime)
  defp sort_key(value), do: value

  defp order(:lt, a, b), do: a < b
  defp order(:gt, a, b), do: a > b
  defp order(:le, a, b), do: a <= b
  defp order(:ge, a, b), do: a >= b

  # Formats: Service.Format's, by the name `as` takes.

  defp format(value, _format, _timezone) when is_nil(value) or value == "", do: nil
  defp format(%Decimal{} = n, "money", _timezone), do: Format.money(n)
  defp format(%Decimal{} = n, format, timezone), do: format(Decimal.to_float(n), format, timezone)
  defp format(%Date{} = date, "date_long", _timezone), do: Format.date_long(date)
  defp format(%DateTime{} = at, "date_long", timezone), do: Format.date_long(at, timezone)
  defp format(%Date{} = date, "date_short", _timezone), do: Format.date_short(date)
  defp format(%DateTime{} = at, "date_short", timezone), do: Format.date_short(at, timezone)
  defp format(%DateTime{} = at, "time", timezone), do: Format.time_short(at, timezone)
  # An expect gives a day for a time, which has no time of day.
  defp format(%Date{}, "time", _timezone), do: nil

  defp format(minutes, "duration", _timezone) when is_number(minutes),
    do: Format.duration(minutes)

  defp format(minutes, "hours", _timezone) when is_number(minutes), do: Format.hours(minutes)
  defp format(n, "number", _timezone) when is_number(n), do: Format.number(n)
  defp format(n, "km", _timezone) when is_number(n), do: Format.km(n)
  defp format(n, "money", _timezone) when is_number(n), do: Format.money(n)

  defp to_text(nil), do: ""
  defp to_text(text) when is_binary(text), do: text
  defp to_text(list) when is_list(list), do: Enum.map_join(list, ", ", &to_text/1)
  defp to_text(%Date{} = date), do: Format.date_long(date)
  defp to_text(%Decimal{} = n), do: Decimal.to_string(n, :normal)
  defp to_text(value), do: to_string(value)

  defp blank?(nil), do: true
  # A picture's bytes are seldom valid text, and never blank.
  defp blank?(text) when is_binary(text), do: String.valid?(text) and String.trim(text) == ""
  defp blank?(_value), do: false
end
