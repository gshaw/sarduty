defmodule App.MCP.Tool.ListActivities do
  @moduledoc "Activities that started in a date range, optionally with one tag. No address."
  @behaviour App.MCP.Tool

  import Ecto.Query

  alias App.MCP.Args
  alias App.MCP.Output
  alias App.Model.Activity
  alias App.Model.Team
  alias App.Repo

  @impl App.MCP.Tool
  def name, do: "list_activities"

  @impl App.MCP.Tool
  def description do
    "Activities that started from one date to another, both included, in the team's time " <>
      "zone, oldest first: id, title, kind (incident, exercise, event), tags, start, and " <>
      "finish. Give tag to list only activities with that tag. Activities deleted in D4H " <>
      "are left out. No address or location."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "from" => %{"type" => "string", "format" => "date", "description" => "First day"},
        "to" => %{"type" => "string", "format" => "date", "description" => "Last day"},
        "tag" => %{
          "type" => "string",
          "description" => "Only activities with this tag, such as Primary Hours"
        }
      },
      "required" => ["from", "to"]
    }
  end

  @impl App.MCP.Tool
  def fields, do: ~w(id title kind tags started_at finished_at)

  @impl App.MCP.Tool
  def call(%Team{} = team, args, _now) do
    with {:ok, _from, _to, start, finish} <- Args.date_range(args, team.timezone) do
      activities =
        build(load(team, start, finish), Args.optional_string(args, "tag"), team.timezone)

      {:ok, activities, length(activities)}
    end
  end

  @doc """
  The output for `activities`, oldest first. With a `tag`, only activities that have it,
  matched without regard to case.
  """
  def build(activities, tag, timezone) do
    activities
    |> Enum.filter(&has_tag?(&1, tag))
    |> Enum.sort_by(&{DateTime.to_unix(&1.started_at), &1.id})
    |> Enum.map(fn activity ->
      %{
        "id" => activity.id,
        "title" => activity.title,
        "kind" => activity.activity_kind,
        "tags" => activity.tags || [],
        "started_at" => Output.datetime(activity.started_at, timezone),
        "finished_at" => Output.datetime(activity.finished_at, timezone)
      }
    end)
  end

  defp has_tag?(_activity, nil), do: true

  defp has_tag?(activity, tag) do
    tag = String.downcase(tag)
    Enum.any?(activity.tags || [], &(String.downcase(&1) == tag))
  end

  defp load(team, start, finish) do
    Activity
    |> where([a], a.team_id == ^team.id)
    |> Activity.not_deleted()
    |> where([a], a.started_at >= type(^start, :naive_datetime))
    |> where([a], a.started_at < type(^finish, :naive_datetime))
    |> select([a], map(a, [:id, :title, :activity_kind, :tags, :started_at, :finished_at]))
    |> Repo.all()
  end
end
