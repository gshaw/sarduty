defmodule App.AI.Tool.TryReport do
  @moduledoc """
  Runs a query on Coast Range SAR, the made-up team (#816), and gives back its rows, so
  Claude catches a wrong answer, such as no rows or a double count, before the team
  admin sees it. Never the team's own records: App.Report.run_sample/3 reads only
  App.SampleRepo. Its answer names Coast Range SAR's groups, qualifications, and tags, so
  Claude tries with those and answers with the team's own.
  """
  @behaviour App.AI.Tool

  alias App.Model.Group
  alias App.Model.Qualification
  alias App.Report
  alias App.Report.Catalog
  alias App.Report.CustomFields
  alias App.Report.Error
  alias App.ViewData.ReportRecords
  alias Web.ReportCSV

  @max_rows 50

  @impl App.AI.Tool
  def name, do: "try_report"

  @impl App.AI.Tool
  def description do
    ~s(Run a query on Coast Range SAR, a made-up team with every field filled, and get ) <>
      ~s(its rows back as text. They are not this team's records: use them to catch a ) <>
      ~s(wrong answer, such as no rows, a double count, or the wrong column. Give values ) <>
      ~s(for what the query picks, such as {"year": "2026"}. Coast Range SAR names its ) <>
      ~s(groups, qualifications, and tags its own way, and the answer lists them: try with ) <>
      ~s(its names, then answer with this team's.)
  end

  @impl App.AI.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "The query"},
        "values" => %{
          "type" => "object",
          "description" => "Picked values and filters by name, such as {\"year\": \"2026\"}"
        }
      },
      "required" => ["query"]
    }
  end

  @impl App.AI.Tool
  def call(%{now: now}, args) do
    case try_query(args, now) do
      {:ok, output, _rows} -> {:ok, output}
      {:error, message} -> {:error, message}
    end
  end

  @doc "`{:ok, output, rows}`, or `{:error, message}`."
  def try_query(args, now) do
    query = args["query"]
    values = values(args["values"])

    with :ok <- check_query(query),
         {:ok, result} <- sample(query, values, now) do
      sample = App.SampleRepo.team()
      records = ReportRecords.names(result, sample, App.SampleRepo)
      [columns | rows] = ReportCSV.table(result, records, sample.timezone)
      {:ok, build(columns, rows, names(sample)), min(length(rows), @max_rows)}
    end
  end

  # Values as a URL gives them, so {"year": 2024} picks 2024 rather than this year. Lists
  # and maps aren't values a query picks, so they go.
  defp values(values) when is_map(values) do
    for {name, value} <- values,
        is_binary(value) or is_number(value),
        into: %{},
        do: {name, to_string(value)}
  end

  defp values(_values), do: %{}

  # Coast Range SAR's names for things, which a query must use to find its rows.
  defp names(sample) do
    %{
      "groups" => sample.id |> Group.get_all(App.SampleRepo) |> Enum.map(& &1.title),
      "qualifications" =>
        sample.id |> Qualification.get_all(App.SampleRepo) |> Enum.map(& &1.title),
      "tags" => sample |> Catalog.read_tag_titles(App.SampleRepo) |> Enum.map(&elem(&1, 0)),
      "custom_fields" =>
        for(
          {on, defs} when is_binary(on) <- CustomFields.read(sample, App.SampleRepo),
          d <- defs,
          do: %{"write" => "`#{d.title}`", "on" => on}
        )
    }
  end

  defp check_query(query) when is_binary(query) and query != "", do: :ok
  defp check_query(_query), do: {:error, "Give query as the report's text."}

  defp sample(query, values, now) do
    case Report.run_sample(query, values, now) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, Error.text(error)}
    end
  end

  @doc """
  The output: the column headers, the first #{@max_rows} rows as text, and Coast Range
  SAR's names for things.
  """
  def build(columns, rows, names) do
    %{
      "team" => "Coast Range SAR",
      "made_up" => true,
      "names" => names,
      "columns" => columns,
      "rows" => Enum.take(rows, @max_rows),
      "more" => length(rows) > @max_rows
    }
  end
end
