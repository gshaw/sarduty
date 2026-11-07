defmodule App.Document.Evaluator do
  @moduledoc """
  Works out what a checked App.Document prints (#918), from a map of the values it reads.
  Pure: the caller runs the reports and loads the pictures.

  A blank value is nil or text with nothing in it: `is null` is true for it, `coalesce`
  skips it, and a flow leaves it out. Text compares exactly, case and all, since an
  `expect` checks what a page prints. A picture stays whatever the caller gave, and
  `qr(link)` is `{:qr, link}` for the printer to draw.
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
  def evaluate(%Document{} = doc, values, timezone) do
    env = %{values: values, timezone: timezone}
    title = doc.title

    %{
      title: title && text_value(title.text, env),
      author: title && title.by && text_value(title.by, env),
      lock: doc.lock,
      keep: Map.new(doc.keep, &{name(&1), value(&1, env)}),
      places: Enum.map(doc.places, &place(&1, doc.fill, env))
    }
  end

  defp place(place, fill, env) do
    %{value: value} = Enum.find(fill, &(&1.place == place.name))
    Map.put(place, :value, place_value(place, value, env))
  end

  defp place_value(%{kind: :flow, across: across?}, {:flow, items}, env),
    do: items |> Enum.map(&item(&1, across?, env)) |> Enum.reject(&is_nil/1)

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
          values = given(expect.given),
          output = evaluate(doc, values, "Etc/UTC"),
          not holds?(expect.check, %{values: outputs(output, values), timezone: "Etc/UTC"}) do
        Error.new(expect.line, "This expect fails: #{described(expect.check, output, values)}")
      end

    if failed == [], do: :ok, else: {:error, failed}
  end

  defp given(given) do
    Map.new(given, fn
      {{:value, name, _}, value, _line} -> {":#{name}", value}
      {{:field, _path, [], _} = field, value, _line} -> {name(field), value}
      {{:range, "TODAY", nil, _}, value, _line} -> {"today", value}
    end)
  end

  # The values, with each place's text and the title, as an expect reads them.
  defp outputs(output, values) do
    output.places
    |> Map.new(&{&1.name, text(output, &1.name)})
    |> Map.merge(%{"title" => output.title, "author" => output.author})
    |> then(&Map.merge(values, &1))
  end

  # The condition, and what each place it reads holds.
  defp described(check, output, values) do
    names = check |> names() |> Enum.uniq()
    read = outputs(output, values)

    shown =
      for name <- names, Map.has_key?(read, name) do
        "#{name} is #{inspect(read[name], printable_limit: 2000)}"
      end

    Enum.join(["#{safe_text(check)}." | shown], " ")
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

  def value({:field, [function], args, _line}, env) when args != [] do
    case String.downcase(function) do
      "coalesce" -> args |> Enum.map(&value(&1, env)) |> Enum.find(&(not blank?(&1)))
      "qr" -> qr(value(hd(args), env))
    end
  end

  def value({:field, _path, [], _line} = field, env), do: Map.get(env.values, name(field))
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

  defp qr(link), do: if(blank?(link), do: nil, else: {:qr, link})

  # As SQL does, a blank compares with nothing.
  defp compare(op, left, right) do
    cond do
      blank?(left) or blank?(right) -> false
      op == :eq -> same?(left, right)
      op == :ne -> not same?(left, right)
      op in [:contains, :starts_with, :ends_with] -> match(op, to_text(left), to_text(right))
      true -> order(op, sort_key(left), sort_key(right))
    end
  end

  defp same?(a, b) when is_number(a) and is_number(b), do: a == b
  defp same?(a, b), do: a == b

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
  defp format(%Date{} = date, "date_long", _timezone), do: Format.date_long(date)
  defp format(%DateTime{} = at, "date_long", timezone), do: Format.date_long(at, timezone)
  defp format(%Date{} = date, "date_short", _timezone), do: Format.date_short(date)
  defp format(%DateTime{} = at, "date_short", timezone), do: Format.date_short(at, timezone)
  defp format(%DateTime{} = at, "time", timezone), do: Format.time_short(at, timezone)

  defp format(minutes, "duration", _timezone) when is_number(minutes),
    do: Format.duration(minutes)

  defp format(minutes, "hours", _timezone) when is_number(minutes), do: Format.hours(minutes)
  defp format(n, "number", _timezone) when is_number(n), do: Format.number(n)
  defp format(n, "km", _timezone) when is_number(n), do: Format.km(n)

  defp to_text(nil), do: ""
  defp to_text(text) when is_binary(text), do: text
  defp to_text(list) when is_list(list), do: Enum.map_join(list, ", ", &to_text/1)
  defp to_text(%Date{} = date), do: Format.date_long(date)
  defp to_text(value), do: to_string(value)

  defp blank?(nil), do: true
  # A picture's bytes are seldom valid text, and never blank.
  defp blank?(text) when is_binary(text), do: String.valid?(text) and String.trim(text) == ""
  defp blank?(_value), do: false
end
