defmodule App.MCP.Tool.NeedsAttention do
  @moduledoc """
  What the team home lists under Needs attention for a team admin, every item (#595). An
  agent's starting point for finding work.
  """
  @behaviour App.MCP.Tool

  alias App.Model.Team
  alias App.ViewData.TeamDashboardViewData

  @impl App.MCP.Tool
  def name, do: "needs_attention"

  @impl App.MCP.Tool
  def description do
    "What needs a team admin's attention now, as the team home lists it. Each item has a " <>
      "key, level (warning or info), title, and detail. Keys include proposed_changes, " <>
      "chores, attendance_to_send, untagged, drafts, expiring, not_seen, and letters. " <>
      "untagged and letters items give their year, and attendance_to_send gives the oldest " <>
      "activity's id. An empty list means nothing is waiting. Start here to find work."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields, do: ~w(key level title detail year activity_id)

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, now) do
    items = team |> TeamDashboardViewData.attention_items(now) |> build()
    {:ok, items, length(items)}
  end

  @doc "The output for the team home's attention items (`TeamAttention.items/3`)."
  def build(items) do
    Enum.map(items, fn item ->
      %{
        "key" => Atom.to_string(item.key),
        "level" => Atom.to_string(item.level),
        "title" => item.title,
        "detail" => item.detail,
        "year" => item[:year],
        "activity_id" => item[:activity_id]
      }
    end)
  end
end
