defmodule App.MCP.Tool.ListActivities do
  @moduledoc """
  Activities that started in a date range, optionally with one tag or one kind of tax
  credit hours, with their length, published flag, attendance counts, and Enough at and
  Full at (#447). No address.
  """
  @behaviour App.MCP.Tool

  import Ecto.Query

  alias App.MCP.Args
  alias App.MCP.Output
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChoreEvent
  alias App.Model.Team
  alias App.Repo

  @hours ~w(primary secondary other none)

  @impl App.MCP.Tool
  def name, do: "list_activities"

  @impl App.MCP.Tool
  def description do
    "Activities that started from one date to another, both included, in the team's time " <>
      "zone, oldest first. Each has its id, title, kind (incident, exercise, event, or " <>
      "chores for the chore activities SAR Duty makes), tags, hours (primary, secondary, " <>
      "other, or none), start, finish, and length in minutes. It also has whether it is " <>
      "published, how many members attended, and how many signed up for it before it " <>
      "starts, with enough_at and full_at: how many signed up is enough, and full, as " <>
      "the team set them in SAR Duty, or null. Give tag to list only activities with that tag, or hours to list only that " <>
      "kind: none finds activities that count no hours. Activities deleted in D4H are " <>
      "left out. No address or location."
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
          "description" =>
            "Only activities with this tag, such as the team's primary_hours_tag " <>
              "from get_team"
        },
        "hours" => %{
          "type" => "string",
          "enum" => @hours,
          "description" => "Only activities that count for these hours"
        }
      },
      "required" => ["from", "to"]
    }
  end

  @impl App.MCP.Tool
  def fields,
    do: ~w(id title kind tags hours started_at finished_at minutes published attended signed_up
         enough_at full_at)

  @impl App.MCP.Tool
  def call(%Team{} = team, args, now) do
    with {:ok, _from, _to, start, finish} <- Args.date_range(args, team.timezone),
         {:ok, hours} <- hours_arg(args) do
      filters = %{tag: Args.optional_string(args, "tag"), hours: hours}

      activities =
        team
        |> load(start, finish, now)
        |> build(filters, Activity.hours_tags(team), team.timezone)

      {:ok, activities, length(activities)}
    end
  end

  defp hours_arg(args) do
    case Args.optional_string(args, "hours") do
      nil -> {:ok, nil}
      hours when hours in @hours -> {:ok, hours}
      _other -> {:error, "Give hours as primary, secondary, other, or none."}
    end
  end

  @doc """
  The output for `activities`, oldest first. `filters` is `%{tag:, hours:}`, either nil:
  a tag matches without regard to case. Each activity has `chore_minutes` set when it is a
  chore activity, and `attended` and `signed_up` counts. `hours_tags` is
  `Activity.hours_tags/1`.
  """
  def build(activities, filters, hours_tags, timezone) do
    activities
    |> Enum.map(&Map.put(&1, :hours, Output.hours_kind(&1.tags, hours_tags)))
    |> Enum.filter(&(has_tag?(&1, filters.tag) and has_hours?(&1, filters.hours)))
    |> Enum.sort_by(&{DateTime.to_unix(&1.started_at), &1.id})
    |> Enum.map(fn activity ->
      %{
        "id" => activity.id,
        "title" => activity.title,
        "kind" => Activity.shown_kind(activity),
        "tags" => activity.tags || [],
        "hours" => activity.hours,
        "started_at" => Output.datetime(activity.started_at, timezone),
        "finished_at" => Output.datetime(activity.finished_at, timezone),
        "minutes" => Output.minutes(activity.started_at, activity.finished_at),
        "published" => activity.is_published == true,
        "attended" => activity.attended,
        "signed_up" => activity.signed_up,
        "enough_at" => activity.enough_at,
        "full_at" => activity.full_at
      }
    end)
  end

  defp has_tag?(_activity, nil), do: true

  defp has_tag?(activity, tag) do
    tag = String.downcase(tag)
    Enum.any?(activity.tags || [], &(String.downcase(&1) == tag))
  end

  defp has_hours?(_activity, nil), do: true
  defp has_hours?(activity, hours), do: activity.hours == hours

  defp load(team, start, finish, now) do
    activities =
      Activity
      |> where([a], a.team_id == ^team.id)
      |> Activity.not_deleted()
      |> where([a], a.started_at >= ^start)
      |> where([a], a.started_at < ^finish)
      |> join(:left, [a], c in subquery(ChoreEvent.totals(team.id)),
        on: c.d4h_activity_id == a.d4h_activity_id
      )
      |> select([a, c], %{
        id: a.id,
        title: a.title,
        activity_kind: a.activity_kind,
        tags: a.tags,
        started_at: a.started_at,
        finished_at: a.finished_at,
        is_published: a.is_published,
        enough_at: a.enough_at,
        full_at: a.full_at,
        chore_minutes: c.minutes
      })
      |> Repo.all()

    ids = Enum.map(activities, & &1.id)
    attended = count_members(Attendance.attended(now), ids)
    signed_up = count_members(Attendance.signed_up(now), ids)

    Enum.map(activities, fn activity ->
      Map.merge(activity, %{
        attended: Map.get(attended, activity.id, 0),
        signed_up: Map.get(signed_up, activity.id, 0)
      })
    end)
  end

  # Members per activity, each once: D4H lets a member have 2 rows on one (#519).
  defp count_members(query, ids) do
    query
    |> where([at], at.activity_id in ^ids)
    |> group_by([at], at.activity_id)
    |> select([at], {at.activity_id, count(at.member_id, :distinct)})
    |> Repo.all()
    |> Map.new()
  end
end
