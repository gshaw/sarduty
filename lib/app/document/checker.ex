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
    "pdf.reference" => :text,
    "pdf.verify_link" => :text
  }
  @one_row ~w(team organization)
  @reserved ~w(team organization pdf today title author)
  @functions ~w(coalesce qr)
  @formats %{
    "date_long" => [:date, :day],
    "date_short" => [:date, :day],
    "time" => [:date],
    "duration" => [:hours, :number],
    "hours" => [:hours, :number],
    "number" => [:number, :km],
    "km" => [:km, :number]
  }

  @doc "The values only printing reads, with their types."
  def print_values, do: @print

  @doc "The formats a value takes after `as`, each with the types it shows."
  def formats, do: @formats

  @doc "The functions a document's values call."
  def functions, do: @functions

  @doc "`{:ok, %Document{}}` with its types, or `{:error, %Error{}}` for the first mistake."
  def check(%Document{} = doc, %Context{} = context) do
    check_where(doc, context)
    reports = Enum.map(doc.reports, &report(&1, doc.for, context)) ++ one_rows(doc, context)
    types = doc |> types(reports) |> asks(doc.asks)
    check_values(doc, types)
    {:ok, %{doc | reports: reports, types: types}}
  catch
    {:report_error, %Error{} = error} -> {:error, error}
  end

  defp check_values(doc, types) do
    if doc.kind == :form and doc.lock,
      do: fail(nil, "Take out lock: an agency writes on a form's PDF.")

    check_places(doc, types)
    check_fill(doc, types)
    check_title(doc.title, types)
    Enum.each(doc.keep, &check_keep(&1, doc.asks, types))
    Enum.each(doc.expects, &check_expect(&1, doc, types))
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

  defp report(report, starts, context) do
    if report.name in @reserved,
      do: fail(report.line, "Give the report another name: #{report.name} is the document's.")

    query = report.query

    for ast <- query.select,
        not match?({:field, _path, [], _line}, ast),
        do: fail(Query.line(ast), "Select fields in a document's report, not #{Query.text(ast)}.")

    for {name, line} <- values(query),
        name not in starts,
        do: fail(line, "Add #{name} after for, or take :#{name} out.")

    Map.put(report, :columns, columns(query, context))
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
    fill = Enum.map(doc.fill, & &1.value)

    expects =
      Enum.flat_map(doc.expects, &[&1.check | Enum.map(&1.given, fn {t, _v, _l} -> t end)])

    defaults = Enum.map(doc.asks, & &1.default)
    [title, doc.keep, defaults, fill, expects] |> List.flatten() |> Enum.reject(&is_nil/1)
  end

  # Field paths, lower case, as `{path, line}`, leaving out a function's name.
  defp fields({:field, [name], args, _line}) when args != [] do
    if String.downcase(name) in @functions, do: Enum.flat_map(args, &fields/1), else: []
  end

  defp fields({:field, path, [], line}), do: [{Enum.map(path, &lower/1), line}]
  defp fields(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> fields()
  defp fields(list) when is_list(list), do: Enum.flat_map(list, &fields/1)
  defp fields(_other), do: []

  # Each name the document can read, and its type.
  defp types(doc, reports) do
    columns =
      for report <- reports,
          column <- report.columns,
          into: %{},
          do: {"#{report.name}.#{lower_path(column.text)}", column.type}

    starts = Map.new(doc.for, &{":#{&1}", :number})
    @print |> Map.merge(columns) |> Map.merge(starts) |> Map.put("today", :day)
  end

  # Asks

  # Each answer's type, in order, so a default reads only the asks above it.
  defp asks(types, asks) do
    Enum.reduce(asks, types, fn ask, types ->
      if Map.has_key?(types, ":#{ask.name}"),
        do:
          fail(ask.line, "Give the ask another name: :#{ask.name} is what the form starts from.")

      Map.put(types, ":#{ask.name}", ask_type(ask, types))
    end)
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

  defp taken?(name, types) do
    prefix = name <> "."

    name in @reserved or Map.has_key?(types, name) or
      types |> Map.keys() |> Enum.any?(&String.starts_with?(&1, prefix))
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
    if Map.has_key?(place, :lines) and not Map.has_key?(place, :pitch),
      do:
        fail(place.line, "Give #{place.name} a pitch with lines: lines counts the page's lines.")

    :ok
  end

  defp check_text_options(place) do
    if place.fit, do: fail(place.line, "Take out fit: only a text place shrinks to fit.")

    for {key, what} <- [
          pitch: "wraps on the page's lines",
          lines: "wraps on the page's lines",
          indent: "starts further in"
        ],
        Map.has_key?(place, key),
        do: fail(place.line, "Take out #{key}: only a text place #{what}.")

    :ok
  end

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

  defp check_fill(doc, types) do
    for fill <- doc.fill do
      case Enum.find(doc.places, &(&1.name == fill.place)) do
        nil -> fail(fill.line, "There is no place #{fill.place}. Add it under places.")
        place -> check_filled(place, fill.value, types, fill.line)
      end
    end

    check_filled_once(doc)
  end

  defp check_filled_once(doc) do
    filled = Enum.map(doc.fill, & &1.place)

    for place <- doc.places do
      case Enum.count(filled, &(&1 == place.name)) do
        0 -> fail(place.line, "Fill #{place.name}: write what goes in it under fill.")
        1 -> :ok
        _more -> fail(place.line, "Fill #{place.name} once.")
      end
    end

    :ok
  end

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

  defp check_expect(expect, doc, types) do
    Enum.each(expect.given, &check_given(&1, types))
    # A tick holds or doesn't, so an expect reads it as a condition.
    outputs =
      doc.places
      |> Map.new(&{&1.name, if(&1.kind == :tick, do: :condition, else: :text)})
      |> Map.merge(%{"title" => :text, "author" => :text})

    if type(expect.check, Map.merge(types, outputs)) != :condition,
      do:
        fail(
          expect.line,
          "Write a condition after expect, such as letter contains 'Total Hours'."
        )

    :ok
  end

  defp check_given({target, value, line}, types) do
    type = type(target, types)

    if type == :image and not is_binary(value),
      do: fail(line, "Give #{text(target)} a value in quotes: it stands for the picture.")

    if type == :day and not match?(%Date{}, value),
      do: fail(line, "Give today a date, such as today = date '2026-01-15'.")

    :ok
  end

  # Types

  @doc false
  def type({:field, [name], args, line}, types) when args != [] do
    case String.downcase(name) do
      "coalesce" -> coalesce_type(args, types, line)
      "qr" -> qr_type(args, types, line)
      other -> fail(line, "There is no function #{other}. Use #{Enum.join(@functions, " or ")}.")
    end
  end

  def type({:field, path, [], line}, types) do
    name = lower_path(Enum.join(path, "."))

    case Map.fetch(types, name) do
      {:ok, type} -> type
      :error -> unknown(name, types, line)
    end
  end

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

  defp unknown(name, types, line) do
    case Expr.closest(name, Map.keys(types)) do
      nil ->
        fail(line, "There is no #{name}. A report's value is report.field, such as hours.total.")

      close ->
        fail(line, "There is no #{name}. Did you mean #{close}?")
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
