defmodule App.MCP.Tool.CheckReport do
  @moduledoc """
  Checks a query against the team's fields without running it (#816), and gives the
  link a team admin opens to run it and save it: New report, or Change report for one
  of the team's own. No rows and no count: the query never runs here.

  Each call is part of a live draft (#834): the first makes its id, and the agent passes
  it back. The team admin's editor open with that draft takes each query the agent
  checks. The reply never depends on running the query, or on whether an editor is
  open: if it did, an agent could ask yes-or-no questions about the team, one per call.
  """
  @behaviour App.MCP.Tool

  use Web, :verified_routes

  alias App.Model.AgentConnection
  alias App.Model.SavedReport
  alias App.Model.Team
  alias App.Report
  alias App.Report.Draft
  alias App.Report.Error

  @impl App.MCP.Tool
  def name, do: "check_report"

  @impl App.MCP.Tool
  def description do
    "Check a report's query against this team's fields without running it. Returns its " <>
      "columns and a link for the team admin, who runs it on the team's records in SAR " <>
      "Duty and saves it. A mistake names its line and the field it meant. Give report_id " <>
      "(a saved report's id from list_reports) to change that report; leave it out for a " <>
      "new one. Values, such as year, are picked on the page. The reply has a draft id: " <>
      "pass it back on each later call for the same report, and the team admin's open " <>
      "page shows each query you check, so they open the link once."
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
        },
        "change" => %{
          "type" => "string",
          "description" =>
            "With report_id: one line on what changed, 100 characters at most, for the report's History"
        },
        "draft" => %{
          "type" => "string",
          "description" => "The draft id an earlier check_report gave, for the same report"
        }
      },
      "required" => ["query"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: ~w(ok columns link draft error)

  @impl App.MCP.Tool
  def call(%Team{} = team, args, now, %AgentConnection{} = connection) do
    query = args["query"]

    with :ok <- check_query(query),
         {:ok, saved} <- saved(team, args["report_id"]),
         {:ok, plan} <- check(query, team, now) do
      draft = draft_id(args["draft"])
      Draft.broadcast(team, connection.user_id, draft, update(args, saved, connection, now))
      {:ok, build(plan, link(team, saved, args, connection.name, draft), draft), 0}
    end
  end

  # The agent's id back, or a new one for a first call or an id we never made.
  defp draft_id(id), do: if(Draft.id?(id), do: id, else: Draft.new_id())

  defp update(args, saved, connection, now) do
    %Draft{
      query: args["query"],
      name: text(args["name"]),
      about: text(args["description"]),
      change: saved && text(args["change"]),
      report_id: saved && saved.id,
      agent: connection.name,
      at: now
    }
  end

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

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

  @doc "The output: the plan's column labels, the link, and the draft's id."
  def build(plan, link, draft) do
    %{
      "ok" => true,
      "columns" => Enum.map(plan.columns, & &1.label),
      "link" => link,
      "draft" => draft
    }
  end

  @doc """
  New report, or Change report for `saved`, with the query, the agent's name, and the
  draft's id in it.
  """
  def link(team, saved, args, agent, draft) do
    params = %{
      "query" => args["query"],
      "name" => args["name"],
      "about" => args["description"],
      "change" => saved && args["change"],
      "agent" => agent,
      "draft" => draft
    }

    editor_url(team, saved, reject_blank(params))
  end

  defp editor_url(team, nil, params), do: url(~p"/teams/#{team}/reports/new?#{params}")

  defp editor_url(team, %SavedReport{} = saved, params),
    do: url(~p"/teams/#{team}/reports/#{saved.id}/edit?#{params}")

  defp reject_blank(params), do: Map.reject(params, fn {_k, v} -> v in [nil, ""] end)
end
