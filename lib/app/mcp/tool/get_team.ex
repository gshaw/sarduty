defmodule App.MCP.Tool.GetTeam do
  @moduledoc """
  The team's name, time zone, today's date there, its hours tags, when D4H data last
  arrived, and whether chores are on, with its chore categories.
  """
  @behaviour App.MCP.Tool

  alias App.MCP.Output
  alias App.Model.Activity
  alias App.Model.ChoreCategory
  alias App.Model.Team

  @impl App.MCP.Tool
  def name, do: "get_team"

  @impl App.MCP.Tool
  def description do
    "The team this token reads: its name, time zone, today's date there, the D4H tags " <>
      "that count as primary and secondary hours on a tax credit letter, the tag for " <>
      "activities that count for no hours (null when the team has none), and when " <>
      "SAR Duty last copied its data from D4H. Also whether chores are on, and its chore " <>
      "categories: id, title, hours (primary or secondary), and whether each is archived. " <>
      "Every time in other tools is in this time zone."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields,
    do: ~w(name subdomain time_zone today primary_hours_tag secondary_hours_tag other_hours_tag
         d4h_refreshed_at chores_enabled chore_categories id title hours archived)

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, now) do
    categories = if Team.chores?(team), do: ChoreCategory.get_all(team.id), else: []
    {:ok, build(team, Activity.hours_tags(team), categories, now), 1}
  end

  @doc "The output. `categories` are the team's chore categories, archived ones too."
  def build(%Team{} = team, hours_tags, categories, now) do
    %{
      "name" => team.name,
      "subdomain" => team.subdomain,
      "time_zone" => team.timezone,
      "today" =>
        now |> DateTime.shift_zone!(team.timezone) |> DateTime.to_date() |> Date.to_iso8601(),
      "primary_hours_tag" => hours_tags.primary,
      "secondary_hours_tag" => hours_tags.secondary,
      "other_hours_tag" => hours_tags[:other],
      "d4h_refreshed_at" => team |> Team.d4h_updated_at() |> Output.datetime(team.timezone),
      "chores_enabled" => Team.chores?(team),
      "chore_categories" =>
        categories
        |> Enum.sort_by(&{String.downcase(&1.title), &1.id})
        |> Enum.map(fn category ->
          %{
            "id" => category.id,
            "title" => category.title,
            "hours" => Atom.to_string(category.hours),
            "archived" => ChoreCategory.archived?(category)
          }
        end)
    }
  end
end
