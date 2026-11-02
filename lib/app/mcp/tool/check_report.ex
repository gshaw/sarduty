defmodule App.MCP.Tool.CheckReport do
  @moduledoc """
  Checks a query against the team's fields without running it (#816), and gives the
  link a team admin opens to run it and save it: New report, or Change report for one
  of the team's own. No rows and no count: the query never runs here.
  """
  @behaviour App.MCP.Tool

  use Web, :verified_routes

  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Report
  alias App.Report.Error

  @impl App.MCP.Tool
  def name, do: "check_report"

  @impl App.MCP.Tool
  def description do
    "Check a report's query against this team's fields without running it. Returns its " <>
      "columns and a link for the team admin, who runs it on the team's records in SAR " <>
      "Duty and saves it. A mistake names its line and the field it meant. Give report_id " <>
      "(a saved report's id from list_reports) to change that report; leave it out for a " <>
      "new one. Values, such as year, are picked on the page."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "The report's query"},
        "name" => %{"type" => "string", "description" => "A name for a new report"},
        "description" => %{"type" => "string", "description" => "One line under its name"},
        "report_id" => %{
          "type" => "integer",
          "description" => "The id of a saved report to change, from list_reports"
        }
      },
      "required" => ["query"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: ~w(ok columns link error)

  @impl App.MCP.Tool
  def call(%Team{} = team, args, now, agent) do
    query = args["query"]

    with :ok <- check_query(query),
         {:ok, saved} <- saved(team, args["report_id"]),
         {:ok, plan} <- check(query, team, now) do
      {:ok, build(plan, link(team, saved, args, agent)), 0}
    end
  end

  defp check_query(query) when is_binary(query) and query != "", do: :ok
  defp check_query(_query), do: {:error, "Give query as the report's text."}

  defp saved(_team, nil), do: {:ok, nil}

  defp saved(team, id) do
    case SavedReport.get(team, id) do
      nil -> {:error, "There is no saved report #{id}. Use an id from list_reports, kind saved."}
      saved -> {:ok, saved}
    end
  end

  defp check(query, team, now) do
    case Report.check(query, team, %{}, now) do
      {:ok, plan} -> {:ok, plan}
      {:error, error} -> {:error, Error.text(error)}
    end
  end

  @doc "The output: the plan's column labels and the link."
  def build(plan, link) do
    %{"ok" => true, "columns" => Enum.map(plan.columns, & &1.label), "link" => link}
  end

  @doc "New report, or Change report for `saved`, with the query and the agent's name in it."
  def link(team, nil, args, agent) do
    params = %{
      "query" => args["query"],
      "name" => args["name"],
      "about" => args["description"],
      "agent" => agent
    }

    url(~p"/teams/#{team}/reports/new?#{reject_blank(params)}")
  end

  def link(team, %SavedReport{} = saved, args, agent) do
    params = %{"query" => args["query"], "agent" => agent}
    url(~p"/teams/#{team}/reports/#{saved.id}/edit?#{reject_blank(params)}")
  end

  defp reject_blank(params), do: Map.reject(params, fn {_k, v} -> v in [nil, ""] end)
end
