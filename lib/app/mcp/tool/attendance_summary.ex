defmodule App.MCP.Tool.AttendanceSummary do
  @moduledoc """
  Hours per member per activity tag and kind, for a date range. Built for a manager's
  agent checking members against the team's attendance policy in one call.
  """
  @behaviour App.MCP.Tool

  import Ecto.Query

  alias App.MCP.Args
  alias App.MCP.Output
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  @impl App.MCP.Tool
  def name, do: "attendance_summary"

  @impl App.MCP.Tool
  def description do
    "Hours each member attended from one date to another, both included, in the team's " <>
      "time zone. For each member: total hours and activities, then hours and activities " <>
      "per activity tag and activity kind (incident, exercise, event). An activity with " <>
      "2 tags counts under both; one with none has tag null. Each attendance counts its " <>
      "own start to finish, or D4H's duration when a time is missing. Overlapping " <>
      "attendances are not merged. Lists every member on the team during the range, " <>
      "with 0 hours when they attended nothing."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "from" => %{"type" => "string", "format" => "date", "description" => "First day"},
        "to" => %{"type" => "string", "format" => "date", "description" => "Last day"}
      },
      "required" => ["from", "to"]
    }
  end

  @impl App.MCP.Tool
  def fields do
    ~w(from to time_zone members member_id name total_hours activities by_tag tag
       activity_kind hours)
  end

  @impl App.MCP.Tool
  def call(%Team{} = team, args, _now) do
    with {:ok, from, to, start, finish} <- Args.date_range(args, team.timezone) do
      members = load_members(team)
      rows = load_rows(team, start, finish)
      summary = summarize(members, rows, start, finish)

      output = %{
        "from" => Date.to_iso8601(from),
        "to" => Date.to_iso8601(to),
        "time_zone" => team.timezone,
        "members" => summary
      }

      {:ok, output, length(summary)}
    end
  end

  @doc """
  One entry per member, by name: those on the team at some point from `start` to
  `finish` (UTC `NaiveDateTime`s), and anyone with a row. `members` have `id`, `name`,
  `joined_at`, and `left_at`. `rows` are attended rows already in the range, each with
  `member_id`, `activity_id`, `started_at`, `finished_at`, `duration_in_minutes`, `tags`,
  and `activity_kind`.
  """
  def summarize(members, rows, start, finish) do
    rows_by_member = Enum.group_by(rows, & &1.member_id)

    members
    |> Enum.filter(&(on_team?(&1, start, finish) or Map.has_key?(rows_by_member, &1.id)))
    |> Enum.sort_by(&{&1.name, &1.id})
    |> Enum.map(&member_summary(&1, Map.get(rows_by_member, &1.id, [])))
  end

  defp member_summary(member, rows) do
    %{
      "member_id" => member.id,
      "name" => member.name,
      "total_hours" => rows |> total_minutes() |> Output.hours(),
      "activities" => activity_count(rows),
      "by_tag" => by_tag(rows)
    }
  end

  defp by_tag(rows) do
    rows
    |> Enum.flat_map(&tag_keys/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {{tag, kind}, _rows} -> {is_nil(tag), tag, kind} end)
    |> Enum.map(&tag_summary/1)
  end

  # The row once under each of its tags, or under nil when it has none.
  defp tag_keys(%{tags: [_ | _] = tags} = row),
    do: tags |> Enum.uniq() |> Enum.map(&{{&1, row.activity_kind}, row})

  defp tag_keys(row), do: [{{nil, row.activity_kind}, row}]

  defp tag_summary({{tag, kind}, rows}) do
    %{
      "tag" => tag,
      "activity_kind" => kind,
      "hours" => rows |> total_minutes() |> Output.hours(),
      "activities" => activity_count(rows)
    }
  end

  defp total_minutes(rows), do: rows |> Enum.map(&minutes/1) |> Enum.sum()

  defp activity_count(rows), do: rows |> Enum.uniq_by(& &1.activity_id) |> length()

  # A row's own times, or D4H's duration when one is missing. A row that finishes before
  # it starts counts nothing.
  defp minutes(%{started_at: %DateTime{} = started, finished_at: %DateTime{} = finished}),
    do: max(DateTime.diff(finished, started, :minute), 0)

  defp minutes(row), do: row.duration_in_minutes || 0

  defp on_team?(member, start, finish) do
    joined = member.joined_at && DateTime.to_naive(member.joined_at)
    left = member.left_at && DateTime.to_naive(member.left_at)

    (is_nil(joined) or NaiveDateTime.before?(joined, finish)) and
      (is_nil(left) or NaiveDateTime.after?(left, start))
  end

  defp load_members(team) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> select([m], map(m, [:id, :name, :joined_at, :left_at]))
    |> Repo.all()
  end

  # Attended rows on activities not deleted, by the row's own start, or the activity's
  # when the row has none.
  defp load_rows(team, start, finish) do
    Attendance
    |> join(:inner, [at], m in assoc(at, :member))
    |> join(:inner, [at], ac in assoc(at, :activity))
    |> where([at, m, ac], m.team_id == ^team.id and ac.team_id == ^team.id)
    |> where([at, m, ac], at.status == "attending" and is_nil(ac.deleted_at))
    |> where(
      [at, m, ac],
      fragment("coalesce(?, ?)", at.started_at, ac.started_at) >= type(^start, :naive_datetime) and
        fragment("coalesce(?, ?)", at.started_at, ac.started_at) < type(^finish, :naive_datetime)
    )
    |> select([at, m, ac], %{
      member_id: at.member_id,
      activity_id: ac.id,
      started_at: at.started_at,
      finished_at: at.finished_at,
      duration_in_minutes: at.duration_in_minutes,
      tags: ac.tags,
      activity_kind: ac.activity_kind
    })
    |> Repo.all()
  end
end
