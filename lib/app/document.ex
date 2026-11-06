defmodule App.Document do
  @moduledoc """
  A document is a PDF SAR Duty prints from a text in `priv/documents/` (#918): what it
  reads, what it says, and where each part sits on the page. The tax credit letter is
  the first. "Template" is taken by kit templates, so in code it's a document.

  The language is the report language's (App.Report): its lexer, its parser for each
  report and every value, and its catalog. Everything here is pure: `parse/1` reads the
  text, `check/2` checks every name against the catalog, and `evaluate/3` turns the
  values a document reads into its title, the values it keeps, and what goes in each
  place. Running the reports, and drawing the page with Typst, is the caller's. The
  language is in docs/documents.md.

  - `for`: the values it starts from, `member` and `year`, read as `:member` and `:year`
  - `reports`: `%{name, query, line}`, each an App.Report.Query; after `check/2` each has
    `columns` too, and `team` and `organization` are reports of the fields it names
  - `title`: `%{text, by, line}`, the PDF's title and author
  - `lock`: `:print` when the PDF can only be printed, or nil
  - `keep`: the values saved with the PDF
  - `places`: `%{name, kind, line, across, level_with}` and its lengths in points, each
    a `:text`, an `:image`, or a `:flow` that stacks values down the page, or across it
  - `fill`: `%{place, value, line}`, a flow's value `{:flow, items}`
  - `expects`: `%{given, check, line}`, worked examples CI runs (`expect/1`)
  - `types`: after `check/2`, each name's type
  """

  alias App.Document.Checker
  alias App.Document.Evaluator
  alias App.Document.Parser
  alias App.Report.Context
  alias App.Report.Query
  alias App.Report.Result

  defstruct name: nil,
            about: nil,
            for: [],
            reports: [],
            title: nil,
            lock: nil,
            keep: [],
            places: [],
            fill: [],
            expects: [],
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
  places}`, each place `%{name, kind, …, value}`.
  """
  def evaluate(%__MODULE__{} = doc, values, timezone) when is_map(values),
    do: Evaluator.evaluate(doc, values, timezone)

  @doc "A place's text, as `expect` reads it: a flow's lines, a blank line for each space."
  defdelegate text(output, place), to: Evaluator

  @doc "`:ok` when every `expect` holds, or `{:error, [%App.Report.Error{}]}` for those that don't."
  defdelegate expect(doc), to: Evaluator
end
