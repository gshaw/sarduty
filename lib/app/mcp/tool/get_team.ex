defmodule App.MCP.Tool.GetTeam do
  @moduledoc "The team's name, time zone, today's date there, and when D4H data last arrived."
  @behaviour App.MCP.Tool

  alias App.MCP.Output
  alias App.Model.Team

  @impl App.MCP.Tool
  def name, do: "get_team"

  @impl App.MCP.Tool
  def description do
    "The team this token reads: its name, time zone, today's date there, and when " <>
      "SAR Duty last copied its data from D4H. Every time in other tools is in this time zone."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields, do: ~w(name subdomain time_zone today d4h_refreshed_at)

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, now), do: {:ok, build(team, now), 1}

  def build(%Team{} = team, now) do
    %{
      "name" => team.name,
      "subdomain" => team.subdomain,
      "time_zone" => team.timezone,
      "today" =>
        now |> DateTime.shift_zone!(team.timezone) |> DateTime.to_date() |> Date.to_iso8601(),
      "d4h_refreshed_at" => team |> Team.d4h_updated_at() |> Output.datetime(team.timezone)
    }
  end
end
