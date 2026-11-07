defmodule App.Document do
  @moduledoc """
  A document is a PDF SAR Duty prints from a text in `priv/documents/` (#918): what it
  reads, what it says, and where each part sits on the page. The tax credit letter is
  the first. "Template" is taken by kit templates, so in code it's a document. A form
  is a document an organization hosts (#950): it starts `form '…'`, prints for an
  activity, asks what SAR Duty can't know, and prints on an agency's own page, with a
  row for each person when it has rows, or on a page its own Typst layout draws.

  The language is the report language's (App.Report): its lexer, its parser for each
  report and every value, and its catalog. Everything here is pure: `parse/1` reads the
  text, `check/2` checks every name against the catalog, and `evaluate/3` turns the
  values a document reads into its title, the values it keeps, and what goes in each
  place. Running the reports, and drawing the page with Typst, is the caller's. The
  language is in docs/documents.md.

  - `kind`: `:document`, or `:form`
  - `for`: the values it starts from, `member` and `year`, read as `:member` and `:year`,
    or a form's `activity`, read as `:activity`
  - `where`: which activities show a form, a condition on `activities`, or nil for all
  - `reports`: `%{name, query, line}`, each an App.Report.Query; after `check/2` each has
    `columns` too, `rows` when it has a row each, and `team` and `organization` are
    reports of the fields it names
  - `consts`: `%{name, values, line}`, each value `%{value, from}`: the first holds
    before any day, and each after it from its day
  - `asks`: `%{name, label, remember, default, choices, hint, each, line}`, what a person
    answers, read as `:name`; `default` is a value, and `remember` starts from the
    team's last answer, which is the caller's to give. With `each`, a report's name, it's
    an answer on each of the report's rows, read in the row by its bare name
  - `computes`: `%{name, each, value, line}` in order: a value worked out from those
    above it, or with `each` one for each of a report's rows
  - `title`: `%{text, by, line}`, the PDF's title and author
  - `lock`: `:print` when the PDF can only be printed, or nil
  - `keep`: the values saved with the PDF
  - `page`: true when the values print on the form's own page PDF, at its size
  - `places`: `%{name, kind, line, across, level_with, fit, page}` and its lengths in
    points, each a `:text`, an `:image`, a `:tick` (an X in a box), or a `:flow` that
    stacks values down the page, or across it; `page` is which page of the form's page.
    A text can have `align`. A form's `:rows` repeats its `places`, a row's, `pitch`
    apart, `lines` to a copy of its page
  - `fill`: `%{place, value, line}`, a flow's value `{:flow, items}`, and a rows place's
    `{:each, report, fills}`, a fill for each of a row's places
  - `expects`: `%{given, check, line}`, worked examples CI runs (`expect/1`); `given`
    holds `{target, value, line}`, and `{:row, report, [{name, value, line}], line}` for
    a row
  - `layout`: `%{text, line}`, a form's Typst layout in place of its places, and the
    line of the text it starts on. Each fill is then a value it reads by name, and
    `fill each` a list of rows
  - `types`: after `check/2`, each name's type
  """

  alias App.Document.Checker
  alias App.Document.Evaluator
  alias App.Document.Parser
  alias App.Report.Context
  alias App.Report.Query
  alias App.Report.Result

  defstruct name: nil,
            kind: :document,
            about: nil,
            for: [],
            where: nil,
            reports: [],
            consts: [],
            asks: [],
            computes: [],
            title: nil,
            lock: nil,
            keep: [],
            page: false,
            places: [],
            fill: [],
            expects: [],
            layout: nil,
            types: %{}

  @dir "documents"

  @doc "The text of the document `name` in priv/documents."
  def read(name) when is_binary(name),
    do:
      :sarduty |> :code.priv_dir() |> Path.join(@dir) |> Path.join("#{name}.txt") |> File.read!()

  @doc "The names of the documents in priv/documents."
  def names do
    :sarduty
    |> :code.priv_dir()
    |> Path.join(@dir)
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".txt"))
    |> Enum.map(&Path.rootname/1)
    |> Enum.sort()
  end

  @doc "`{:ok, %Document{}}`, or `{:error, %App.Report.Error{}}` for the first mistake."
  defdelegate parse(text), to: Parser

  @doc """
  `{:ok, %Document{}}` with every name checked against the catalog and typed, or
  `{:error, %App.Report.Error{}}` for the first mistake. Reads nothing.
  """
  def check(%__MODULE__{} = doc, %Context{} = context), do: Checker.check(doc, context)

  @doc "A checked document's reports, as `{name, query}`: what to run before `evaluate/3`."
  def queries(%__MODULE__{} = doc), do: Enum.map(doc.reports, &{&1.name, &1.query})

  @doc """
  A form's query that finds the activity `:activity` when the form shows on it: `select
  id from activities where id = :activity and` its `where`. Run it with the activity's
  id given: no row, and the form isn't for that activity.
  """
  def shown_on(%__MODULE__{where: where} = doc) do
    %Query{select: [id], from_line: line} = query = activities_shown_on(doc)
    this = {:op, :eq, id, {:value, "activity", line}, line}
    %{query | where: if(where, do: {:op, :and, this, where, line}, else: this)}
  end

  @doc """
  A form's query for every activity it shows on: `select id from activities where` its
  `where`. Trying a form on Coast Range SAR lists them.
  """
  def activities_shown_on(%__MODULE__{where: where}) do
    line = if where, do: Query.line(where), else: 1

    %Query{
      select: [{:field, ["id"], [], line}],
      from: "activities",
      from_line: line,
      where: where
    }
  end

  @doc """
  A checked form's answers from what a person typed, by the ask's name: `{:ok, values}`
  with each as `:name`, ready for `evaluate/3`, or `{:error, %{name => message}}`. A
  blank answer is left out, so its default holds.

  An `ask each` answer is typed for each row, `%{name => %{row => text}}`, where `row`
  is the row's key, such as `"member:12"`. It's `{name, row}` in the values, and its
  error `%{name => %{row => message}}`.
  """
  def answers(%__MODULE__{} = doc, typed) when is_map(typed) do
    results = Enum.flat_map(doc.asks, &read_answers(doc, &1, Map.get(typed, &1.name)))
    errors = Enum.reduce(results, %{}, &put_error/2)
    if errors == %{}, do: {:ok, Map.new(results, &answered/1)}, else: {:error, errors}
  end

  defp read_answers(doc, ask, typed) do
    type = ask_type(doc, ask)
    for {row, text} <- typed_texts(ask, typed), do: {ask, row, answer(ask, type, text)}
  end

  defp answered({ask, nil, {:ok, value}}), do: {":#{ask.name}", value}
  defp answered({ask, row, {:ok, value}}), do: {{ask.name, row}, value}

  defp put_error({ask, nil, {:error, message}}, errors), do: Map.put(errors, ask.name, message)

  defp put_error({ask, row, {:error, message}}, errors),
    do: Map.update(errors, ask.name, %{row => message}, &Map.put(&1, row, message))

  defp put_error(_answered, errors), do: errors

  @doc "A checked form's type for an ask's answer: `:text`, `:number`, or `:day`."
  def ask_type(%__MODULE__{types: types}, %{each: nil, name: name}), do: types[":#{name}"]

  def ask_type(%__MODULE__{types: types}, %{each: report, name: name}),
    do: types |> Checker.row_types(report) |> Map.get(name)

  # What a person typed, as `{row, text}`, leaving out blanks: row nil for one answer.
  defp typed_texts(%{each: nil}, text), do: trimmed(nil, text)

  defp typed_texts(_ask, rows) when is_map(rows),
    do: Enum.flat_map(rows, fn {row, text} -> trimmed(to_string(row), text) end)

  defp typed_texts(_ask, _other), do: []

  defp trimmed(row, text) when is_binary(text) or is_number(text) do
    case text |> to_string() |> String.trim() do
      "" -> []
      text -> [{row, text}]
    end
  end

  defp trimmed(_row, _blank), do: []

  defp answer(%{choices: [_ | _] = choices}, _type, text) do
    if text in choices,
      do: {:ok, text},
      else: {:error, "Pick #{Enum.join(choices, " or ")}."}
  end

  defp answer(_ask, :number, text) do
    case {Integer.parse(text), Float.parse(text)} do
      {{n, ""}, _float} -> {:ok, n}
      {_integer, {n, ""}} -> {:ok, n}
      _other -> {:error, "Enter a number, such as 3."}
    end
  end

  defp answer(_ask, :day, text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "Enter a date, such as 2026-11-06."}
    end
  end

  defp answer(_ask, :text, text), do: {:ok, text}

  @doc """
  `values` with a report's first row added, each column as `report.column`. A record
  is its name or title, from `records` as App.ViewData.ReportRecords.names/3 loads them.
  A report with no row adds nothing, so its values are blank.
  """
  def put_row(values, name, %Query{} = query, %Result{} = result, records \\ %{}) do
    case result.rows do
      [] ->
        values

      [row | _] ->
        query.select
        |> Enum.zip(result.columns)
        |> Enum.zip(row)
        |> Enum.into(values, fn {{ast, column}, value} ->
          {"#{name}.#{Evaluator.name(ast)}", cell(value, column, records)}
        end)
    end
  end

  @doc """
  `values` with every row of a report that has a row each, as `name`: a list of `%{key,
  values}`, each column by its name. `key` is the row's first member or item, as
  `"member:12"`, which keeps its answers; a record's value is its name.
  """
  def put_rows(values, name, %Query{} = query, %Result{} = result, records \\ %{}) do
    names = Enum.map(query.select, &Evaluator.name/1)
    key_at = Enum.find_index(result.columns, &keyed?/1)

    rows =
      for row <- result.rows,
          do: %{
            key: row_key(row, result.columns, key_at),
            values: cells(row, names, result, records)
          }

    Map.put(values, name, rows)
  end

  defp cells(row, names, result, records) do
    cells =
      row
      |> Enum.zip(result.columns)
      |> Enum.map(fn {value, column} -> cell(value, column, records) end)

    names |> Enum.zip(cells) |> Map.new()
  end

  defp keyed?(%{type: {:record, kind}}), do: kind in [:member, :item]
  defp keyed?(_column), do: false

  defp row_key(_row, _columns, nil), do: nil

  defp row_key(row, columns, at) do
    %{type: {:record, kind}} = Enum.at(columns, at)

    case Enum.at(row, at) do
      nil -> nil
      id -> "#{kind}:#{id}"
    end
  end

  defp cell(nil, _column, _records), do: nil

  defp cell(id, %{type: {:record, kind}}, records) do
    case records |> Map.get(kind, %{}) |> Map.get(id) do
      %{name: name} -> name
      %{title: title} -> title
      nil -> nil
    end
  end

  defp cell(value, _column, _records), do: value

  @doc """
  What a checked document prints from `values`: a map of names to values, `:year` for a
  value it starts from, `hours.total` for a report's, `team.logo` for one only printing
  reads, and `today`. Dates show in `timezone`. Gives `%{title, author, lock, keep,
  places}`, each place `%{name, kind, …, value}`, and a form's `layout` and `fills`,
  each value its layout reads by name.
  """
  def evaluate(%__MODULE__{} = doc, values, timezone) when is_map(values),
    do: Evaluator.evaluate(doc, values, timezone)

  @doc """
  The values a checked document reads from `values`, worked out as `evaluate/3` works
  them out: each answer at its default, each report's rows with their answers and
  values, and each compute. A form's page shows them.
  """
  def values(%__MODULE__{} = doc, values, timezone) when is_map(values),
    do: Evaluator.prepare(doc, values, timezone).values

  @doc """
  A row's value `name`, such as a person's total, as the form's `fill each` prints it:
  with the format a row's place gives it, `total as money`, or as text. A form's page
  shows each row's total this way.
  """
  def printed(%__MODULE__{fill: fill}, name, value, timezone) do
    format =
      Enum.find_value(fill, fn
        %{value: {:each, _report, fills}} -> Enum.find_value(fills, &format_of(&1.value, name))
        _fill -> nil
      end)

    Evaluator.printed(value, format, timezone)
  end

  defp format_of({:as, {:field, [field], [], _}, format, _line}, name),
    do: if(String.downcase(field) == name, do: format)

  defp format_of(_value, _name), do: nil

  @doc "A place's text, as `expect` reads it: a flow's lines, a blank line for each space."
  defdelegate text(output, place), to: Evaluator

  @doc "`:ok` when every `expect` holds, or `{:error, [%App.Report.Error{}]}` for those that don't."
  defdelegate expect(doc), to: Evaluator
end
