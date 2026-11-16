defmodule App.AI.Tool.CheckReport do
  @moduledoc """
  Checks a query against the asker's team without running it: its columns, or the
  mistake with its line, as the editor would show it. No rows and no count.
  """
  @behaviour App.AI.Tool

  alias App.Report
  alias App.Report.Error

  @impl App.AI.Tool
  def name, do: "check_report"

  @impl App.AI.Tool
  def description do
    "Check a query against this team's fields without running it. Returns its column " <>
      "labels, or the mistake with its line and the field it meant. Check every query " <>
      "before you give it as your answer."
  end

  @impl App.AI.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{"query" => %{"type" => "string", "description" => "The query"}},
      "required" => ["query"]
    }
  end

  @impl App.AI.Tool
  def call(%{team: team, now: now}, %{"query" => query}) when is_binary(query) and query != "" do
    case Report.check(query, team, %{}, now) do
      {:ok, plan} -> {:ok, %{"ok" => true, "columns" => Enum.map(plan.columns, & &1.label)}}
      {:error, error} -> {:error, Error.text(error)}
    end
  end

  def call(_context, _args), do: {:error, "Give query as the report's text."}
end
