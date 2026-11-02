defmodule App.MCP.Tool.TryReport do
  @moduledoc """
  Runs a query on Coast Range SAR, the made-up team (#816), and gives back its rows, so
  an agent catches a wrong answer, such as no rows or a double count, before the team
  admin sees it. Never the team's own records: App.Report.run_sample/3 reads only
  App.SampleRepo.
  """
  @behaviour App.MCP.Tool

  alias App.Model.Team
  alias App.Report
  alias App.Report.Error
  alias App.ViewData.ReportRecords
  alias Web.ReportCSV

  @max_rows 50

  @impl App.MCP.Tool
  def name, do: "try_report"

  @impl App.MCP.Tool
  def description do
    "Run a report's query on Coast Range SAR, a made-up team with every field filled, " <>
      "and get its rows back as text. They are not this team's records: use them to " <>
      "catch a wrong answer, such as no rows, a double count, or the wrong column, " <>
      "before check_report. Give values for what the query picks, such as {\"year\": " <>
      "\"2026\"}. Coast Range SAR's names for groups and tags may differ from this team's."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "The report's query"},
        "values" => %{
          "type" => "object",
          "description" => "Picked values and filters by name, such as {\"year\": \"2026\"}"
        }
      },
      "required" => ["query"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: ~w(team made_up columns rows more)

  @impl App.MCP.Tool
  def call(%Team{}, args, now, _agent) do
    query = args["query"]
    values = if is_map(args["values"]), do: args["values"], else: %{}

    with :ok <- check_query(query),
         {:ok, result} <- run(query, values, now) do
      sample = App.SampleRepo.team()
      records = ReportRecords.names(result, sample, App.SampleRepo)
      [columns | rows] = ReportCSV.table(result, records, sample.timezone)
      {:ok, build(columns, rows), min(length(rows), @max_rows)}
    end
  end

  defp check_query(query) when is_binary(query) and query != "", do: :ok
  defp check_query(_query), do: {:error, "Give query as the report's text."}

  defp run(query, values, now) do
    case Report.run_sample(query, values, now) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, Error.text(error)}
    end
  end

  @doc "The output: the column headers and the first #{@max_rows} rows, as text."
  def build(columns, rows) do
    %{
      "team" => "Coast Range SAR",
      "made_up" => true,
      "columns" => columns,
      "rows" => Enum.take(rows, @max_rows),
      "more" => length(rows) > @max_rows
    }
  end
end
