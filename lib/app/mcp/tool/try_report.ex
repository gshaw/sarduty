defmodule App.MCP.Tool.TryReport do
  @moduledoc """
  Runs a query on Coast Range SAR, the made-up team (#816), and gives back its rows. The
  work is App.AI.Tool.TryReport's, which AI writing calls too: never the team's own
  records.
  """
  @behaviour App.MCP.Tool

  alias App.AI.Tool.TryReport
  alias App.Model.Team

  @impl App.MCP.Tool
  def name, do: TryReport.name()

  @impl App.MCP.Tool
  def description do
    "Run a report's query on Coast Range SAR, a made-up team with every field filled, " <>
      "and get its rows back as text. They are not this team's records: use them to " <>
      "catch a wrong answer, such as no rows, a double count, or the wrong column, " <>
      "before check_report. Give values for what the query picks, such as {\"year\": " <>
      "\"2026\"}. Coast Range SAR names its groups, qualifications, and tags its own way, " <>
      "and the output lists them: try with its names, then give check_report this team's."
  end

  @impl App.MCP.Tool
  def input_schema, do: TryReport.input_schema()

  @impl App.MCP.Tool
  def fields,
    do: ~w(team made_up columns rows more names groups qualifications tags custom_fields write on)

  @impl App.MCP.Tool
  def call(%Team{}, args, now, _connection), do: TryReport.try_query(args, now)
end
