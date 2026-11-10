defmodule App.Document.Checker do
  @moduledoc """
  Checks a parsed App.Document against the report catalog (#918), and types each name it
  reads. Pure: App.Report.Compiler checks each report without its SQL, and nothing is
  read.

  A document reads a report's columns as `report.column`, the team's and its
  organization's fields as `team.legal_name` and `organization.name` with no report of
  its own, the values it starts from as `:member` and `:year`, and `today`. A few values
  only print, and no report reads them: the team's and the organization's logos, the
  team's signature, and the PDF's reference and verify link. `qr()` makes a link a QR
  code.

  A form (#950) starts from `:activity`, and its `where` is checked as a report's on
  activities. Each answer is `:name`, typed by its default: text, a number, or a date.

  A form works out values too (#950): a `const`, read on a day when it has several, and
  each `compute`, which reads only what's above it. A report that `compute each` or `ask
  each` names has a row each: within it a bare name reads the row's column, answer, or
  value first, and elsewhere only `sum(people.total)` reads it. Arithmetic takes numbers,
  never a duration, which is minutes: `hours(duration)` reads it in hours.

  A form's rows place (#950) holds a row's places, filled by `fill each people into
  rows` from each of report `people`'s rows. A plain fill also reads `page` and `pages`,
  and `sum(rows.total)` over the rows on its copy of the page.

  A form with a `layout` (#950) has no places: each fill is a value its Typst layout
  reads by name, text, a picture, or a condition, and `fill each equipment into items`
  a list of rows, each text or conditions. `{:fill, name}` holds each one's kind, and
  `{:fill, list, name}` a row's.

  Besides each name's type, `types` holds what a scope needs under tuple keys:
  `{:rows, report}` is the names of a row each and their types, `{:const, name}` marks a
  const, and `{:dated, name}` the day a const first changes.
  """

  alias App.Document
  alias App.Report.Compiler
  alias App.Report.Context
  alias App.Report.Error
  alias App.Report.Expr
  alias App.Report.Query

  # The values only printing reads, never a report: the signature stays out of reports.
  @print %{
    "team.logo" => :image,
    "team.signature" => :image,
    "organization.logo" => :image,
    "pdf.verify_link" => :text
  }
  @one_row ~w(team organization)
  @reserved ~w(team organization pdf today title author page pages)
  @functions ~w(coalesce qr hours days floor round)
  @calls ~w(min max sum)
  @numbers [:number, :km, :money]
  @formats %{
    "date_long" => [:date, :day],
    "date_short" => [:date, :day],
    "time" => [:date],
    "duration" => [:hours, :number],
    "hours" => [:hours, :number],
    "number" => [:number, :km],
    "km" => [:km, :number],
    "money" => [:money, :number]
  }

  @doc "The values only printing reads, with their types."
  def print_values, do: @print

  @doc "The formats a value takes after `as`, each with the types it shows."
  def formats, do: @formats

  @doc "The functions a document's values call."
  def functions, do: @functions ++ @calls

  @doc "The names a report `people` has a row each of, and their types: `%{name => type}`."
  def row_types(types, report), do: Map.get(types, {:rows, report}, %{})

  @doc "`{:ok, %Document{}}` with its types, or `{:error, %Error{}}` for the first mistake."
  def check(%Document{} = doc, %Context{} = context) do
    check_where(doc, context)
    rows = rows_reports(doc)

    reports =
      Enum.map(doc.reports, &report(&1, doc.for, rows, context)) ++ one_rows(doc, context)

    types =
      doc
      |> types(reports)
      |> consts(doc.consts)
      |> asks(doc.asks)
      |> computes(doc.computes)

    types = check_values(doc, types)
    {:ok, %{doc | reports: reports, types: types}}
  catch
    {:report_error, %Error{} = error} -> {:error, error}
  end

  # The reports `compute each` and `ask each` name: each has a row each.
  defp rows_reports(doc) do
    fills =
      for %{value: {:each, report, _fills}, line: line} <- doc.fill,
          do: %{each: report, line: line}

    for %{each: each} = item <- doc.asks ++ doc.computes ++ fills, each != nil, uniq: true do
      if each in @one_row or not Enum.any?(doc.reports, &(&1.name == each)),
        do:
          fail(item.line, "There is no report #{each}. Write report #{each} and its query above.")

      each
    end
  end

  defp check_values(doc, types) do
    if doc.kind == :form and doc.lock,
      do: fail(nil, "Take out lock: an agency writes on a form's PDF.")

    check_places(doc, types)
    types = Map.merge(types, check_fill(doc, types))
    check_title(doc.title, types)
    Enum.each(doc.keep, &check_keep(&1, doc.asks, types))
    Enum.each(doc.verify_shows, &check_shown(&1, types))
    Enum.each(doc.needs, &check_need(&1, types))
    check_email(doc.email, types)
    Enum.each(doc.expects, &check_expect(&1, doc, types))
    types
  end

  # Which activities show a form: its where, checked as a report's on activities. It
  # reads no answers, since it decides whether the form shows before anyone answers.
  defp check_where(%Document{where: nil}, _context), do: :ok

  defp check_where(%Document{where: where} = doc, context) do
    for {name, line} <- walk(where),
        do: fail(line, "Take out :#{name}: where reads only the activity's fields.")

    columns(Document.shown_on(doc), context)
    :ok
  end

  # Reports

  defp report(report, starts, rows, context) do
    if report.name in @reserved,
      do: fail(report.line, "Give the report another name: #{report.name} is the document's.")

    query = report.query

    for ast <- query.select,
        not match?({:field, _path, [], _line}, ast),
        do: fail(Query.line(ast), "Select fields in a document's report, not #{Query.text(ast)}.")

    for {name, line} <- values(query),
        name not in starts,
        do: fail(line, "Add #{name} after for, or take :#{name} out.")

    report
    |> Map.put(:columns, columns(query, context))
    |> Map.put(:rows, report.name in rows)
  end

  defp columns(query, context) do
    case Compiler.select_columns(query, context) do
      {:ok, columns} -> columns
      {:error, error} -> throw({:report_error, error})
    end
  end

  # The `:name` values a query reads, as `{name, line}`.
  defp values(%Query{} = query),
    do: [query.select, query.where, query.order_by] |> walk() |> Enum.uniq_by(&elem(&1, 0))

  defp walk({:value, name, line}), do: [{name, line}]
  defp walk(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> walk()
  defp walk(list) when is_list(list), do: Enum.flat_map(list, &walk/1)
  defp walk(_other), do: []

  # The team's and the organization's fields a document names, each read as a report of
  # its own, so the catalog checks them as it checks any report.
  defp one_rows(doc, context) do
    fields = doc |> asts() |> Enum.flat_map(&fields/1)

    for subject <- @one_row,
        used = for({[^subject, name], line} <- fields, read?(subject, name), do: {name, line}),
        used != [],
        do: one_row(subject, used, context)
  end

  defp read?(subject, name), do: not Map.has_key?(@print, "#{subject}.#{name}")

  defp one_row(subject, [{_name, line} | _] = used, context) do
    select =
      used
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.map(fn {name, line} -> {:field, [name], [], line} end)

    query = %Query{select: select, from: subject, from_line: line}
    %{name: subject, query: query, line: line, columns: columns(query, context)}
  end

  # Every value the document writes, outside its reports.
  defp asts(doc) do
    title = if doc.title, do: [doc.title.text, doc.title.by], else: []
    fill = Enum.flat_map(doc.fill, &fill_values/1)

    expects =
      Enum.flat_map(doc.expects, &[&1.check | for({t, _v, _l} <- &1.given, do: t)])

    [title, doc.keep, named_values(doc), fill, expects]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # The values an ask's default, a compute, a verify shows line, a need, and the email
  # hold.
  defp named_values(doc) do
    email = if doc.email, do: [doc.email.subject, {:flow, doc.email.body}], else: []

    Enum.map(doc.asks, & &1.default) ++
      Enum.map(doc.computes, & &1.value) ++
      Enum.map(doc.verify_shows, & &1.value) ++ doc.needs ++ email
  end

  defp fill_values(%{value: {:each, _report, fills}}), do: Enum.map(fills, & &1.value)
  defp fill_values(fill), do: [fill.value]

  # Field paths, lower case, as `{path, line}`, leaving out a function's name.
  defp fields({:field, [name], args, _line}) when args != [] do
    if String.downcase(name) in @functions, do: Enum.flat_map(args, &fields/1), else: []
  end

  defp fields({:field, path, [], line}), do: [{Enum.map(path, &lower/1), line}]
  defp fields(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> fields()
  defp fields(list) when is_list(list), do: Enum.flat_map(list, &fields/1)
  defp fields(_other), do: []

  # Each name the document can read, and its type. A report with a row each is read
  # within its rows.
  defp types(doc, reports) do
    {rows, first} = Enum.split_with(reports, &Map.get(&1, :rows, false))

    columns =
      for report <- first,
          column <- report.columns,
          into: %{},
          do: {"#{report.name}.#{lower_path(column.text)}", column.type}

    each =
      Map.new(rows, fn report ->
        {{:rows, report.name}, Map.new(report.columns, &{lower_path(&1.text), &1.type})}
      end)

    starts = Map.new(doc.for, &{":#{&1}", :number})

    @print
    |> Map.merge(columns)
    |> Map.merge(each)
    |> Map.merge(starts)
    |> Map.put("today", :day)
  end

  # Whether a value's name is taken: a word the document keeps, a value's name, a
  # report's, or a const's.
  defp taken?(name, types) do
    prefix = name <> "."

    name in @reserved or Map.has_key?(types, name) or Map.has_key?(types, {:rows, name}) or
      types |> names() |> Enum.any?(&String.starts_with?(&1, prefix))
  end

  # The names in `types`, without the tuple keys a scope needs.
  defp names(types), do: types |> Map.keys() |> Enum.filter(&is_binary/1)

  # Consts

  defp consts(types, consts) do
    Enum.reduce(consts, types, fn const, types ->
      check_const_name(const, types)
      [type | _] = kinds = Enum.map(const.values, &literal_type(&1.value))

      if Enum.uniq(kinds) != [type],
        do:
          fail(const.line, "Give #{const.name} values of one kind: all numbers, text, or dates.")

      types
      |> Map.put(const.name, type)
      |> Map.put({:const, const.name}, true)
      |> dated(const)
    end)
  end

  defp check_const_name(const, types) do
    if taken?(const.name, types),
      do: fail(const.line, "Give the const another name: #{const.name} is used above.")

    for {{:rows, report}, row} <- types, Map.has_key?(row, const.name) do
      fail(const.line, "Give the const another name: #{const.name} is one of #{report}'s values.")
    end

    :ok
  end

  defp dated(types, %{values: [_one]}), do: types

  defp dated(types, %{name: name, values: [_ | [later | _]]}),
    do: Map.put(types, {:dated, name}, later.from)

  # Computes

  # Each value, in order, so it reads only what's above it. One for each row goes with
  # its report's row.
  defp computes(types, computes) do
    Enum.reduce(computes, types, fn
      %{each: nil} = compute, types ->
        if taken?(compute.name, types),
          do: fail(compute.line, "Give the compute another name: #{compute.name} is used above.")

        Map.put(types, compute.name, compute_type(compute, types))

      %{each: report} = compute, types ->
        row = row_types(types, report)

        if Map.has_key?(row, compute.name),
          do:
            fail(
              compute.line,
              "Give the compute another name: #{compute.name} is one of #{report}'s values."
            )

        if taken?(compute.name, types),
          do: fail(compute.line, "Give the compute another name: #{compute.name} is used above.")

        type = compute_type(compute, Map.merge(types, row))
        Map.put(types, {:rows, report}, Map.put(row, compute.name, type))
    end)
  end

  defp compute_type(compute, types) do
    case type(compute.value, types) do
      :image -> fail(compute.line, "Compute a number, text, or a date, not a picture.")
      type -> type
    end
  end

  # Asks

  # Each answer's type, in order, so a default reads only the asks above it. An answer
  # for each row goes with its report's row, kept by the row's member or item.
  defp asks(types, asks) do
    Enum.reduce(asks, types, fn
      %{each: nil} = ask, types ->
        if Map.has_key?(types, ":#{ask.name}"),
          do:
            fail(
              ask.line,
              "Give the ask another name: :#{ask.name} is what the form starts from."
            )

        Map.put(types, ":#{ask.name}", ask_type(ask, types))

      %{each: report} = ask, types ->
        row = row_types(types, report)
        check_ask_each(ask, report, row)

        Map.put(
          types,
          {:rows, report},
          Map.put(row, ask.name, ask_type(ask, Map.merge(types, row)))
        )
    end)
  end

  defp check_ask_each(ask, report, row) do
    if Map.has_key?(row, ask.name),
      do: fail(ask.line, "Give the ask another name: #{ask.name} is one of #{report}'s values.")

    if ask.remember,
      do: fail(ask.line, "Take out remember: an answer for each row starts from its default.")

    if not Enum.any?(row, fn {_name, type} -> type in [{:record, :member}, {:record, :item}] end),
      do:
        fail(
          ask.line,
          "Select member or item in report #{report}: each row's answer is kept by it."
        )

    :ok
  end

  defp ask_type(%{choices: [_one]} = ask, _types),
    do: fail(ask.line, "Give choose two answers or more, such as choose 'Yes', 'No'.")

  defp ask_type(%{choices: [_ | _]} = ask, types) do
    check_choice(ask, types)
    :text
  end

  defp ask_type(%{default: nil}, _types), do: :text

  defp ask_type(ask, types) do
    case type(ask.default, types) do
      type when type in [:text, :choice] -> :text
      type when type in [:number, :day] -> type
      _other -> fail(ask.line, "Give default text, a number, or a date, such as default 0.")
    end
  end

  defp check_choice(%{default: nil}, _types), do: :ok

  defp check_choice(%{default: {:literal, value, line}, choices: choices}, _types) do
    if value not in choices,
      do: fail(line, "Make the default one of the choices: #{quoted(choices)}.")

    :ok
  end

  defp check_choice(ask, types) do
    if type(ask.default, types) not in [:text, :choice],
      do: fail(ask.line, "Make the default one of the choices: #{quoted(ask.choices)}.")

    :ok
  end

  defp quoted(choices), do: Enum.map_join(choices, " or ", &"'#{&1}'")

  # Places

  defp check_places(doc, types) do
    names = Enum.map(doc.places, & &1.name)

    for place <- doc.places do
      if taken?(place.name, types),
        do: fail(place.line, "Give the place another name: #{place.name} is a value's.")

      if Enum.count(names, &(&1 == place.name)) > 1,
        do: fail(place.line, "Give the place another name: #{place.name} is used twice.")

      check_place(place, doc)
    end
  end

  # A rows place repeats a row of places down a form's page, `pitch` apart, `lines` to a
  # copy of the page. There's one, and only on a form's own page.
  defp check_place(%{kind: :rows} = place, doc) do
    if not doc.page,
      do: fail(place.line, "Take out #{place.name}, or add page: rows repeat a form's page.")

    if Enum.count(doc.places, &(&1.kind == :rows)) > 1,
      do: fail(place.line, "Write one rows place: a form's rows fill one part of its page.")

    check_rows_options(place)
    Enum.each(place.places, &check_row_place(&1, place))
  end

  defp check_place(place, doc) do
    check_position(place)

    if place.across and place.kind != :flow,
      do: fail(place.line, "Take out across: only a flow stacks across.")

    check_level_with(place, doc.places)
    check_page(place, doc)
    check_text_options(place)

    if place.kind == :tick and not Map.has_key?(place, :size),
      do: fail(place.line, "Give #{place.name} a size: the side of its box, such as size 9pt.")

    :ok
  end

  defp check_rows_options(place) do
    for key <- [:top, :pitch, :lines], not Map.has_key?(place, key) do
      fail(
        place.line,
        "Give #{place.name} a top, a pitch, and lines, such as top 260pt, pitch 14pt, lines 18."
      )
    end

    for key <- [:left, :right, :bottom, :width, :height, :size, :leading, :gap, :pad, :indent],
        Map.has_key?(place, key) do
      fail(place.line, "Take out #{key}: rows take a top, a pitch, lines, and a page.")
    end

    if place.fit or Map.has_key?(place, :align),
      do: fail(place.line, "Write fit and align on a row's places, not on #{place.name}.")

    :ok
  end

  # A row's places sit in each row: `top` is from the row's top.
  defp check_row_place(place, rows) do
    if place.kind not in [:text, :tick],
      do: fail(place.line, "Make #{place.name} text or tick: a row holds text and ticks.")

    if Enum.count(rows.places, &(&1.name == place.name)) > 1,
      do: fail(place.line, "Give the place another name: #{place.name} is used twice.")

    unless Map.has_key?(place, :left) or Map.has_key?(place, :right),
      do: fail(place.line, "Say where #{place.name} sits across the page: left or right.")

    if in_row?(place),
      do: :ok,
      else:
        fail(
          place.line,
          "Give #{place.name} a top in its row, if any: it sits in each of #{rows.name}."
        )

    check_text_options(place)

    if place.kind == :tick and not Map.has_key?(place, :size),
      do: fail(place.line, "Give #{place.name} a size: the side of its box, such as size 9pt.")

    :ok
  end

  defp in_row?(place),
    do: not Map.has_key?(place, :bottom) and place.page == 1 and is_nil(place.level_with)

  defp check_level_with(%{level_with: nil}, _places), do: :ok

  defp check_level_with(place, places) do
    case Enum.find(places, &down_flow?(&1, place.level_with)) do
      nil ->
        fail(place.line, "Write level with and a flow that stacks down, not #{place.level_with}.")

      %{page: page} when page != place.page ->
        fail(place.line, "Put #{place.name} on page #{page}, where #{place.level_with} is.")

      _flow ->
        :ok
    end
  end

  defp down_flow?(place, name),
    do: place.name == name and place.kind == :flow and not place.across

  defp check_page(%{page: 1}, _doc), do: :ok
  defp check_page(_place, %Document{page: true}), do: :ok

  defp check_page(place, _doc),
    do:
      fail(place.line, "Take out page #{place.page}, or add page: only a form's page has pages.")

  # `fit` keeps one line and shrinks it to its width; `pitch` wraps it on the page's lines.
  defp check_text_options(%{kind: :text, fit: true} = place) do
    check_align(place)

    for key <- [:pitch, :indent],
        Map.has_key?(place, key),
        do: fail(place.line, "Write fit or #{key}, not both: fit keeps the text on one line.")

    unless Map.has_key?(place, :width) or
             (Map.has_key?(place, :left) and Map.has_key?(place, :right)),
           do:
             fail(
               place.line,
               "Give #{place.name} a width, or left and right: fit shrinks the text to it."
             )

    :ok
  end

  # `indent` starts the first line further in, after a printed label; `lines` caps how
  # many of the page's lines it wraps on, so a long text shrinks to fit them.
  defp check_text_options(%{kind: :text} = place) do
    check_align(place)

    if Map.has_key?(place, :lines) and not Map.has_key?(place, :pitch),
      do:
        fail(place.line, "Give #{place.name} a pitch with lines: lines counts the page's lines.")

    :ok
  end

  defp check_text_options(place) do
    if place.fit, do: fail(place.line, "Take out fit: only a text place shrinks to fit.")

    if Map.has_key?(place, :align),
      do: fail(place.line, "Take out align: only a text place lines up its text.")

    for {key, what} <- [
          pitch: "wraps on the page's lines",
          lines: "wraps on the page's lines",
          indent: "starts further in"
        ],
        Map.has_key?(place, key),
        do: fail(place.line, "Take out #{key}: only a text place #{what}.")

    :ok
  end

  # Right or center lines up text in a width it knows.
  defp check_align(%{align: align} = place) when align in [:right, :center] do
    unless Map.has_key?(place, :width) or
             (Map.has_key?(place, :left) and Map.has_key?(place, :right)),
           do:
             fail(
               place.line,
               "Give #{place.name} a width, or left and right: align #{align} lines it up in it."
             )

    :ok
  end

  defp check_align(_place), do: :ok

  defp check_position(place) do
    unless Map.has_key?(place, :left) or Map.has_key?(place, :right),
      do: fail(place.line, "Say where #{place.name} sits across the page: left or right.")

    unless Map.has_key?(place, :top) or Map.has_key?(place, :bottom) or place.level_with,
      do:
        fail(
          place.line,
          "Say where #{place.name} sits down the page: top, bottom, or level with."
        )

    :ok
  end

  # Fill

  # Each place filled once, or with a layout each value's kind.
  defp check_fill(%Document{layout: %{}} = doc, types) do
    check_names_once(doc.fill, "Give the value another name: ~s is filled twice.")

    Enum.reduce(doc.fill, %{}, fn fill, kinds ->
      if taken?(fill.place, types),
        do: fail(fill.line, "Give the value another name: #{fill.place} is used above.")

      Map.merge(kinds, layout_kinds(fill, types))
    end)
  end

  defp check_fill(doc, types) do
    types = fill_scope(doc, types)

    for fill <- doc.fill do
      case Enum.find(doc.places, &(&1.name == fill.place)) do
        nil -> fail(fill.line, "There is no place #{fill.place}. Add it under places.")
        place -> check_filled(place, fill.value, types, fill.line)
      end
    end

    check_filled_once(doc.places, doc.fill)
    %{}
  end

  defp check_names_once(fills, message) do
    for {name, [_, second | _]} <- Enum.group_by(fills, & &1.place) do
      fail(second.line, String.replace(message, "~s", name))
    end

    :ok
  end

  # A layout's value is text, a picture, or a condition; a row's, text or a condition.
  defp layout_kinds(%{place: list, value: {:each, report, fills}}, types) do
    check_names_once(fills, "Give the value another name: ~s is in each row twice.")
    row = Map.merge(types, row_types(types, report))

    Map.new(fills, fn fill ->
      case layout_kind(fill.value, row) do
        :image ->
          fail(fill.line, "Fill #{fill.place} with text or a condition: a row holds no pictures.")

        kind ->
          {{:fill, list, fill.place}, kind}
      end
    end)
  end

  defp layout_kinds(%{place: name, value: value}, types),
    do: %{{:fill, name} => layout_kind(value, types)}

  defp layout_kind(value, types) do
    case type(value, types) do
      type when type in [:condition, :bool] -> :condition
      :image -> :image
      _text -> :text
    end
  end

  # What a fill reads besides the document's values: which copy of the form's page it's
  # on and how many there are, `page` and `pages`, and a rows place's rows on that copy,
  # as `sum(rows.total)`.
  defp fill_scope(doc, types) do
    types = Map.merge(types, %{"page" => :number, "pages" => :number})

    Enum.reduce(doc.fill, types, fn
      %{place: place, value: {:each, report, _fills}}, types ->
        Map.put(types, {:rows, place}, row_types(types, report))

      _fill, types ->
        types
    end)
  end

  defp check_filled_once(places, fill) do
    filled = Enum.map(fill, & &1.place)

    for place <- places do
      case Enum.count(filled, &(&1 == place.name)) do
        0 -> fail(place.line, "Fill #{place.name}: write what goes in it under fill.")
        1 -> :ok
        _more -> fail(place.line, "Fill #{place.name} once.")
      end
    end

    :ok
  end

  defp check_filled(%{kind: :rows} = rows, {:each, report, fills}, types, _line) do
    # A row reads its own values, never the copy's rows.
    row = types |> Map.delete({:rows, rows.name}) |> Map.merge(row_types(types, report))

    for fill <- fills do
      case Enum.find(rows.places, &(&1.name == fill.place)) do
        nil ->
          fail(fill.line, "There is no place #{fill.place} in #{rows.name}. Add it under it.")

        place ->
          check_filled(place, fill.value, row, fill.line)
      end
    end

    check_filled_once(rows.places, fills)
  end

  defp check_filled(%{kind: :rows} = place, _value, _types, line),
    do:
      fail(
        line,
        "Fill #{place.name} with fill each and a report, such as fill each people into #{place.name}."
      )

  defp check_filled(place, {:each, _report, _fills}, _types, line),
    do: fail(line, "Fill #{place.name} under fill: fill each fills a rows place.")

  defp check_filled(%{kind: :flow} = place, {:flow, items}, types, _line),
    do: Enum.each(items, &check_item(&1, place, types))

  defp check_filled(%{kind: :tick} = place, value, types, line) do
    if type(value, types) not in [:condition, :bool],
      do:
        fail(
          line,
          "Fill #{place.name} with a condition, such as :injured > 0: it ticks when it holds."
        )

    :ok
  end

  defp check_filled(%{kind: :image} = place, value, types, line) do
    if type(value, types) != :image,
      do:
        fail(line, "Fill #{place.name} with an image, such as team.logo or qr(pdf.verify_link).")
  end

  defp check_filled(place, value, types, line), do: check_text(value, types, line, place.name)

  defp check_item({:space, _count, condition, _line}, _place, types),
    do: check_condition(condition, types)

  defp check_item({:image, expr, _options, condition, line}, place, types) do
    if place.across, do: fail(line, "Take out image: a flow across holds images alone.")
    check_condition(condition, types)

    if type(expr, types) != :image,
      do: fail(line, "Write an image after image, such as team.signature.")
  end

  defp check_item(value, %{across: true} = place, types) do
    if type(value, types) != :image,
      do: fail(Query.line(value), "Fill #{place.name} with images: it stacks them across.")
  end

  defp check_item(value, place, types),
    do: check_text(value, types, Query.line(value), place.name)

  defp check_text(value, types, line, place) do
    case type(value, types) do
      :image -> fail(line, "Write image before it: #{place} holds it as a picture, not text.")
      :condition -> fail(line, "Write a value, not a condition: use if … then … else.")
      _type -> :ok
    end
  end

  defp check_condition(nil, _types), do: :ok

  defp check_condition(condition, types) do
    if type(condition, types) != :condition,
      do:
        fail(
          Query.line(condition),
          "Write a condition after if, such as member.address is not null."
        )

    :ok
  end

  defp check_title(nil, _types), do: :ok

  defp check_title(title, types) do
    check_text(title.text, types, title.line, "title")
    if title.by, do: check_text(title.by, types, title.line, "by")
    :ok
  end

  # Only what a report reads is kept: never a value only printing reads, like the signature.
  # A need is one of the team's or organization's settings, a field or a picture.
  defp check_need({:field, [subject, _name], [], line} = field, types) do
    if lower(subject) not in @one_row, do: need_mistake(line)
    _type = type(field, types)
    :ok
  end

  defp check_need(expr, _types), do: need_mistake(Query.line(expr))

  defp need_mistake(line),
    do: fail(line, "Write the team's settings after needs, such as team.signer.")

  defp check_email(nil, _types), do: :ok

  defp check_email(%{subject: subject, body: body, line: line}, types) do
    check_text(subject, types, line, "the email's subject")
    Enum.each(body, &check_item(&1, %{across: false, name: "the email's body"}, types))
  end

  # A verify page shows text from what the document reads, never what only prints: the
  # page shows it to anyone holding the paper, so it's text a reviewer can read.
  defp check_shown(%{value: value, line: line, label: label}, types) do
    for {path, at} <- fields(value),
        Map.has_key?(@print, Enum.join(path, ".")),
        do: fail(at, "Show a value a report reads: #{Enum.join(path, ".")} only prints.")

    check_text(value, types, line, "'#{label}'")
  end

  defp check_keep({:field, path, [], line}, _asks, types) do
    name = lower_path(Enum.join(path, "."))

    cond do
      Map.has_key?(@print, name) ->
        fail(line, "Keep a value a report reads: #{name} only prints.")

      Map.has_key?(types, name) and String.contains?(name, ".") ->
        :ok

      true ->
        type({:field, path, [], line}, types)
    end
  end

  # An answer is kept as it was given.
  defp check_keep({:value, name, line}, asks, _types) do
    if Enum.any?(asks, &(&1.name == name)),
      do: :ok,
      else: fail(line, "Keep a report's value or an answer, such as hours.total, not :#{name}.")
  end

  defp check_keep(expr, _asks, _types),
    do: fail(Query.line(expr), "Keep a report's value, such as hours.total, not #{text(expr)}.")

  # An expect that gives one row checks it: its names read the row first.
  defp check_expect(expect, doc, types) do
    # A tick holds or doesn't, so an expect reads it as a condition.
    outputs =
      doc.places
      |> Enum.reject(&(&1.kind == :rows))
      |> Map.new(&{&1.name, if(&1.kind == :tick, do: :condition, else: :text)})
      |> Map.merge(layout_outputs(types))
      |> Map.merge(%{"title" => :text, "author" => :text})

    if expect |> given_scope(types) |> Map.merge(outputs) |> then(&type(expect.check, &1)) !=
         :condition,
       do:
         fail(
           expect.line,
           "Write a condition after expect, such as letter contains 'Total Hours'."
         )

    :ok
  end

  # A layout's values, each by its kind; a list of rows isn't read.
  defp layout_outputs(types), do: for({{:fill, name}, kind} <- types, into: %{}, do: {name, kind})

  # The names an expect's check reads: one that gives one row reads the row first.
  defp given_scope(expect, types) do
    rows =
      for {:row, report, values, line} <- expect.given, do: check_row(report, values, line, types)

    for {_target, _value, _line} = given <- expect.given, do: check_given(given, types)

    case rows do
      [report] -> Map.merge(types, row_types(types, report))
      _none_or_more -> types
    end
  end

  # A row's values, each one of the report's: a column, an answer, or a compute.
  defp check_row(report, values, line, types) do
    if not Map.has_key?(types, {:rows, report}),
      do:
        fail(
          line,
          "There is no report #{report} with a row each. Give a row of one that compute each reads."
        )

    row = row_types(types, report)

    for {name, value, line} <- values do
      case Map.fetch(row, name) do
        {:ok, type} when type in [:date, :day] and not is_struct(value, Date) ->
          fail(line, "Give #{name} a date, such as #{name} 2026-06-01.")

        {:ok, _type} ->
          :ok

        :error ->
          fail(line, "#{report} has no #{name}.#{did_you_mean(name, Map.keys(row))}")
      end
    end

    report
  end

  # A const reads as given, whatever day it is.
  defp check_given({{:field, [name], [], _}, _value, _line} = given, types) do
    if Map.has_key?(types, {:const, lower(name)}), do: :ok, else: check_typed(given, types)
  end

  defp check_given(given, types), do: check_typed(given, types)

  defp check_typed({target, value, line}, types) do
    type = type(target, types)

    if type == :image and not is_binary(value),
      do: fail(line, "Give #{text(target)} a value in quotes: it stands for the picture.")

    if type == :day and not match?(%Date{}, value),
      do: fail(line, "Give today a date, such as today = date '2026-01-15'.")

    :ok
  end

  # Types

  @doc false
  def type({:field, [name], args, line}, types) when args != [],
    do: function_type(String.downcase(name), args, types, line)

  def type({:field, path, [], line}, types) do
    name = lower_path(Enum.join(path, "."))

    case {Map.fetch(types, name), Map.get(types, {:dated, name})} do
      {{:ok, _type}, %Date{} = day} ->
        fail(
          line,
          "Read #{name} on a day, such as #{name} on started_at: it changes on #{Date.to_iso8601(day)}."
        )

      {{:ok, type}, nil} ->
        type

      {:error, _day} ->
        unknown(path, name, types, line)
    end
  end

  def type({:call, name, distinct?, args, line}, types) when name in @calls do
    if distinct?, do: fail(line, "Take out distinct: #{name} takes values, not a report's rows.")
    if name == "sum", do: sum_type(args, types, line), else: min_max_type(name, args, types, line)
  end

  def type({:call, name, _distinct?, _args, line}, _types), do: no_function(name, line)

  def type({:arith, _op, left, right, _line}, types) do
    number(left, types)
    number(right, types)
    :number
  end

  # `km_rate on started_at`: a const's value on a day.
  def type({:on, {:field, [name], [], _}, day, line}, types) do
    name = lower(name)

    if not Map.has_key?(types, {:const, name}),
      do: fail(line, "Read a const on a day, such as km_rate on started_at, not #{name}.")

    if type(day, types) not in [:date, :day],
      do: fail(line, "Write a day after on, such as #{name} on started_at.")

    Map.fetch!(types, name)
  end

  def type({:on, expr, _day, line}, _types),
    do: fail(line, "Read a const on a day, such as km_rate on started_at, not #{text(expr)}.")

  def type({:value, name, line}, types) do
    case Map.fetch(types, ":#{name}") do
      {:ok, type} -> type
      :error -> fail(line, "Add #{name} after for or ask for it above, or take :#{name} out.")
    end
  end

  def type({:literal, value, _line}, _types), do: literal_type(value)

  # The report language's TODAY: the team's date today.
  def type({:range, "TODAY", nil, _line}, types), do: Map.fetch!(types, "today")

  def type({:text, parts, _line}, types) do
    for {expr, format} <- Enum.reject(parts, &is_binary/1) do
      check_text(expr, types, Query.line(expr), "text")
      if format, do: format_type(expr, format, types)
    end

    :text
  end

  def type({:as, expr, format, _line}, types), do: format_type(expr, format, types)

  def type({:when, value, condition, _line}, types) do
    check_condition(condition, types)
    type(value, types)
  end

  def type({:if, condition, yes, no, line}, types) do
    check_condition(condition, types)
    a = type(yes, types)
    b = type(no, types)

    if :image in [a, b] and a != b,
      do: fail(line, "Write two images, or two values, after then and else.")

    a
  end

  def type({:op, op, left, right, line}, types) when op in [:and, :or] do
    check_condition(left, types)
    check_condition(right, types)
    _ = line
    :condition
  end

  def type({:op, :like, _left, _right, line}, _types),
    do: fail(line, "Use contains, starts with, or ends with: a document has no like.")

  def type({:op, _op, left, right, _line}, types) do
    compared(left, types)
    compared(right, types)
    :condition
  end

  def type({:not, expr, _line}, types) do
    check_condition(expr, types)
    :condition
  end

  def type({:is_null, expr, _negated?, _line}, types) do
    type(expr, types)
    :condition
  end

  def type({:in, expr, items, _negated?, _line}, types) do
    compared(expr, types)
    Enum.each(items, &compared(&1, types))
    :condition
  end

  def type(expr, _types),
    do: fail(Query.line(expr), "A document's value can't use #{text(expr)}.")

  defp compared(expr, types) do
    case type(expr, types) do
      :condition -> fail(Query.line(expr), "Write and or or between conditions.")
      :image -> fail(Query.line(expr), "Compare #{text(expr)} with is null or is not null.")
      type -> type
    end
  end

  defp function_type("coalesce", args, types, line), do: coalesce_type(args, types, line)
  defp function_type("qr", args, types, line), do: qr_type(args, types, line)
  defp function_type("hours", args, types, line), do: hours_type(args, types, line)
  defp function_type("round", args, types, line), do: round_type(args, types, line)

  defp function_type("days", args, types, line),
    do: one_number(args, types, line, "days", "days(hours)")

  defp function_type("floor", args, types, line),
    do: one_number(args, types, line, "floor", "floor(hours / 3)")

  defp function_type(name, _args, _types, line), do: no_function(name, line)

  # Numbers

  # A value arithmetic takes: a number, never a duration, which is kept in minutes.
  defp number(expr, types) do
    case type(expr, types) do
      type when type in @numbers ->
        type

      :hours ->
        fail(
          Query.line(expr),
          "Read #{text(expr)} in hours with hours(#{text(expr)}): a duration is kept in minutes."
        )

      _other ->
        fail(Query.line(expr), "Use a number here, not #{text(expr)}.")
    end
  end

  defp one_number([value], types, _line, _name, _example) do
    number(value, types)
    :number
  end

  defp one_number(_args, _types, line, name, example),
    do: fail(line, "Give #{name} one number, such as #{example}.")

  defp round_type([value], types, _line), do: one_number([value], types, nil, "round", "")

  defp round_type([value, {:literal, places, _}], types, _line)
       when is_integer(places) and places >= 0,
       do: one_number([value], types, nil, "round", "")

  defp round_type(_args, _types, line),
    do: fail(line, "Give round a number and how many decimals, such as round(total, 2).")

  defp min_max_type(_name, [_, _ | _] = args, types, _line) do
    Enum.each(args, &number(&1, types))
    :number
  end

  defp min_max_type(name, _args, _types, line),
    do: fail(line, "Give #{name} two numbers or more, such as #{name}(0, total).")

  # `hours(started_at, finished_at)`, the hours between two times, or `hours(duration)`.
  defp hours_type([from, to], types, line) do
    for time <- [from, to], type(time, types) not in [:date, :day] do
      fail(line, "Give hours two times, such as hours(started_at, finished_at).")
    end

    :number
  end

  defp hours_type([duration], types, line) do
    if type(duration, types) != :hours,
      do:
        fail(line, "Give hours a duration, or two times, such as hours(started_at, finished_at).")

    :number
  end

  defp hours_type(_args, _types, line),
    do: fail(line, "Give hours two times, such as hours(started_at, finished_at).")

  # `sum(people.total)`: a column, answer, or value added up over a report's rows.
  defp sum_type([{:field, [report | [_ | _] = path], [], _}], types, line) do
    report = lower(report)
    name = lower_path(Enum.join(path, "."))

    case types |> Map.get({:rows, report}) |> then(&(&1 && Map.fetch(&1, name))) do
      nil ->
        sum_type(nil, types, line)

      {:ok, type} when type in @numbers ->
        :number

      {:ok, :hours} ->
        :hours

      {:ok, _type} ->
        fail(line, "Add up a number: #{report}.#{name} is not one.")

      :error ->
        row = row_types(types, report)
        fail(line, "#{report} has no #{name}.#{did_you_mean(name, Map.keys(row))}")
    end
  end

  defp sum_type(_args, _types, line),
    do: fail(line, "Give sum one column of a report with a row each, such as sum(people.total).")

  defp no_function(name, line),
    do:
      fail(
        line,
        "There is no function #{name}. Use #{Enum.join(@functions ++ @calls, ", ")}."
      )

  defp coalesce_type([_one], _types, line),
    do: fail(line, "Give coalesce two values or more: it takes the first that isn't blank.")

  defp coalesce_type([first | rest], types, line) do
    type = type(first, types)

    for expr <- rest,
        type == :image != (type(expr, types) == :image),
        do: fail(line, "Give coalesce all images, or no images.")

    type
  end

  defp qr_type([link], types, line) do
    if type(link, types) != :text, do: fail(line, "Give qr a link, such as qr(pdf.verify_link).")
    :image
  end

  defp qr_type(_args, _types, line),
    do: fail(line, "Give qr one link, such as qr(pdf.verify_link).")

  defp format_type(expr, format, types) do
    type = type(expr, types)

    case Map.fetch(@formats, format) do
      :error ->
        fail(
          Query.line(expr),
          "There is no format #{format}. Use #{Enum.join(Map.keys(@formats), ", ")}."
        )

      {:ok, fits} ->
        if type not in fits, do: wrong_format(expr, format, type)
        :text
    end
  end

  defp wrong_format(expr, format, type) do
    case for {name, types} <- @formats, type in types, do: name do
      [] -> fail(Query.line(expr), "Take out as #{format}: #{text(expr)} shows one way.")
      names -> fail(Query.line(expr), "Show #{text(expr)} as #{Enum.join(names, " or ")}.")
    end
  end

  defp literal_type(value) when is_binary(value), do: :text
  defp literal_type(value) when is_number(value), do: :number
  defp literal_type(value) when is_boolean(value), do: :bool
  defp literal_type(%Date{}), do: :day
  defp literal_type(nil), do: nil

  defp unknown([report | [_ | _]], name, types, line) when is_map_key(types, {:rows, report}),
    do: fail(line, "Add up #{name} with sum(#{name}): #{report} has a row each.")

  defp unknown(_path, name, types, line) do
    case Expr.closest(name, names(types)) do
      nil ->
        fail(line, "There is no #{name}. A report's value is report.field, such as hours.total.")

      close ->
        fail(line, "There is no #{name}. Did you mean #{close}?")
    end
  end

  defp did_you_mean(name, names) do
    case Expr.closest(name, names) do
      nil -> ""
      close -> " Did you mean #{close}?"
    end
  end

  # A path's names in lower case; a custom field's title keeps its own.
  defp lower_path(text),
    do: text |> String.split(".") |> Enum.map_join(".", &lower/1)

  defp lower("`" <> _ = title), do: title
  defp lower(name), do: String.downcase(name)

  defp text(expr) do
    Query.text(expr)
  rescue
    FunctionClauseError -> "it"
  end

  defp fail(line, message), do: throw({:report_error, Error.new(line, message)})
end
