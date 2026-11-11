defmodule App.MCP.Tool.ListReports do
  @moduledoc """
  The team's reports (#816): built in, its own, and the lists drawn by a report, with
  each one's name, description, and query. Never their rows, and never a saved report's
  values: those can be text a team admin typed, such as a member's ID or a search.
  """
  @behaviour App.MCP.Tool

  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Report.BuiltIn
  alias App.Report.Lists

  @impl App.MCP.Tool
  def name, do: "list_reports"

  @impl App.MCP.Tool
  def description do
    "The team's reports: built in (kind built_in, id its slug), the team's own (kind " <>
      "saved, id a number), and the lists that run on reports (kind list). Each has its " <>
      "name, description, and query. Start from one when a " <>
      "team admin asks for something close to it. Never the rows: reports run in SAR Duty."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields, do: ~w(reports kind id name description query)

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, _now, _connection) do
    output = build(BuiltIn.all(), SavedReport.get_all(team), Lists.all())
    {:ok, output, length(output["reports"])}
  end

  @doc "The output, from the built-in reports, the team's saved ones, and the lists."
  def build(built_in, saved, lists) do
    built_in = Enum.map(built_in, &report("built_in", &1.slug, &1))
    saved = Enum.map(saved, &report("saved", &1.id, &1))
    lists = Enum.map(lists, &report("list", &1.slug, Map.put(&1, :about, nil)))
    %{"reports" => built_in ++ saved ++ lists}
  end

  defp report(kind, id, report) do
    %{
      "kind" => kind,
      "id" => id,
      "name" => report.name,
      "description" => report.about,
      "query" => report.query
    }
  end
end
