defmodule App.MCP.Tool.NeedsAttention do
  @moduledoc """
  What the team home lists under Needs attention for a team admin, every item (#595). An
  agent's starting point for finding work.
  """
  @behaviour App.MCP.Tool

  alias App.MCP.Output
  alias App.Model.Team
  alias App.ViewData.TeamDashboardViewData

  @impl App.MCP.Tool
  def name, do: "needs_attention"

  @impl App.MCP.Tool
  def description do
    "What needs a team admin's attention now, as the team home lists it. Each item has a " <>
      "key, level (danger, warning, or info), title, and detail. Keys include chores, " <>
      "attendance_to_send, no_shows, untagged, drafts, expiring, not_seen, and letters. " <>
      "untagged and letters items give their year, and attendance_to_send and no_shows " <>
      "give the oldest activity's id. An item a team admin snoozed comes last, with " <>
      "snoozed_until, when it shows again. An empty list means nothing is waiting. " <>
      "Start here to find work."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields, do: ~w(key level title detail year activity_id snoozed_until)

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, now) do
    items = team |> TeamDashboardViewData.attention_items(now) |> build(team.timezone)
    {:ok, items, length(items)}
  end

  @doc "The output for the team home's attention items (`TeamAttention.items/4`). Never the members behind an item.."
  def build(items, timezone) do
    Enum.map(items, fn item ->
      %{
        "key" => Atom.to_string(item.key),
        "level" => Atom.to_string(item.level),
        "title" => item.title,
        "detail" => item.detail,
        "year" => item[:year],
        "activity_id" => item[:activity_id],
        "snoozed_until" => item[:snooze] && Output.datetime(item.snooze.until, timezone)
      }
    end)
  end
end
