defmodule App.MCP.Tool.ReportFields do
  @moduledoc """
  How to write a report (#816): the language, every subject and field, and the team's
  names for things: its groups, qualifications, tags, hours tags, and custom fields. How
  the team is organized, never who is in it or what they did.
  """
  @behaviour App.MCP.Tool

  use Web, :verified_routes

  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.Group
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Report.Catalog
  alias App.Report.Language

  @targets [{"activity", "activities"}, {"member", "members"}, {"equipment", "equipment"}]

  @impl App.MCP.Tool
  def name, do: "report_fields"

  @impl App.MCP.Tool
  def description do
    "Start here. How to write a SAR Duty report: the language, with an example for each " <>
      "clause, every subject and field, and this team's names for things: its groups, " <>
      "qualifications, tags, hours tags, and custom fields. Reports run in SAR Duty: you " <>
      "write the query, try it on a made-up team with try_report, and give the team admin " <>
      "the link check_report returns. You never see the team's members or records."
  end

  @impl App.MCP.Tool
  def input_schema, do: %{"type" => "object", "properties" => %{}}

  @impl App.MCP.Tool
  def fields,
    do: ~w(team language language_url groups qualifications tags hours_tags primary secondary
         other custom_fields title on)

  @impl App.MCP.Tool
  def call(%Team{} = team, _args, _now, _agent) do
    names = %{
      groups: titles(Group.get_all(team.id)),
      qualifications: titles(Qualification.get_all(team.id)),
      tags: team |> Catalog.read_tag_titles(App.Repo) |> Enum.map(&elem(&1, 0)),
      hours_tags: Activity.hours_tags(team),
      custom_fields: custom_fields(team)
    }

    {:ok, build(team, names), 1}
  end

  defp titles(records), do: Enum.map(records, & &1.title)

  defp custom_fields(team) do
    for {target, on} <- @targets,
        field <- CustomField.get_all(team.id, target),
        do: {field.title, on}
  end

  @doc "The output, from the team's names for things."
  def build(%Team{} = team, names) do
    %{
      "team" => team.name,
      "language" => Language.markdown(),
      "language_url" => url(~p"/agents/reports"),
      "groups" => names.groups,
      "qualifications" => names.qualifications,
      "tags" => names.tags,
      "hours_tags" => %{
        "primary" => names.hours_tags.primary,
        "secondary" => names.hours_tags.secondary,
        "other" => names.hours_tags[:other]
      },
      "custom_fields" =>
        Enum.map(names.custom_fields, fn {title, on} -> %{"title" => title, "on" => on} end)
    }
  end
end
