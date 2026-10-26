defmodule App.MCP.Tool.ListAttendance do
  @moduledoc """
  One activity's attendance rows as SAR Duty last copied them (#595), with times and the
  status in the glossary's words, which change when the activity starts. No contact
  details, and not the activity's address or description.
  """
  @behaviour App.MCP.Tool

  import Ecto.Query

  alias App.MCP.Output
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChoreEvent
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  @impl App.MCP.Tool
  def name, do: "list_attendance"

  @impl App.MCP.Tool
  def description do
    "One activity's attendance, as SAR Duty last copied it. Each row has its attendance " <>
      "id, member id and name, status, start, finish, minutes, and when the member " <>
      "replied. Before the activity starts, status is no_reply, signed_up, or " <>
      "cant_make_it. Once it starts, status is attended or absent. A member can have 2 " <>
      "rows on one activity. The activity comes with its title, kind, tags, hours " <>
      "(primary, secondary, other, or none), start, finish, length in minutes, and " <>
      "whether it is published. Get activity ids from list_activities."
  end

  @impl App.MCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "activity_id" => %{"type" => "integer", "description" => "SAR Duty's activity id"}
      },
      "required" => ["activity_id"]
    }
  end

  @impl App.MCP.Tool
  def fields do
    ~w(activity id title kind tags hours started_at finished_at minutes published rows
       attendance_id member_id member_name status replied_at)
  end

  @impl App.MCP.Tool
  def call(%Team{} = team, args, now) do
    case Repo.get_by(Activity, id: args["activity_id"], team_id: team.id) do
      %Activity{deleted_at: nil} = activity ->
        activity = ChoreEvent.put_chore_minutes(activity)
        rows = load_rows(team, activity)
        output = build(activity, rows, Activity.hours_tags(team), team.timezone, now)
        {:ok, output, length(output["rows"])}

      %Activity{} ->
        {:error, "Activity #{args["activity_id"]} was deleted in D4H, so it has no attendance."}

      nil ->
        {:error, "No activity #{inspect(args["activity_id"])} on this team."}
    end
  end

  @doc """
  The output for `activity` and its `rows`, each with `id`, `member_id`, `member_name`,
  `status` (D4H's, lowercased), `started_at`, `finished_at`, `duration_in_minutes`, and
  `replied_at`. Rows go by member name, then start. Times are in `tz`.
  """
  def build(%Activity{} = activity, rows, hours_tags, tz, now) do
    %{
      "activity" => %{
        "id" => activity.id,
        "title" => activity.title,
        "kind" => Activity.shown_kind(activity),
        "tags" => activity.tags || [],
        "hours" => Output.hours_kind(activity.tags, hours_tags),
        "started_at" => Output.datetime(activity.started_at, tz),
        "finished_at" => Output.datetime(activity.finished_at, tz),
        "minutes" => Output.minutes(activity.started_at, activity.finished_at),
        "published" => activity.is_published == true
      },
      "rows" =>
        rows
        |> Enum.sort_by(&{&1.member_name, sort_time(&1.started_at), &1.id})
        |> Enum.map(&row(&1, activity, tz, now))
    }
  end

  defp row(row, activity, tz, now) do
    %{
      "attendance_id" => row.id,
      "member_id" => row.member_id,
      "member_name" => row.member_name,
      "status" => status(row, activity, now),
      "started_at" => Output.datetime(row.started_at, tz),
      "finished_at" => Output.datetime(row.finished_at, tz),
      "minutes" => Output.minutes(row.started_at, row.finished_at) || row.duration_in_minutes,
      "replied_at" => Output.datetime(row.replied_at, tz)
    }
  end

  defp status(row, activity, now) do
    case Attendance.status_word(row, activity, now) do
      word when is_atom(word) -> Atom.to_string(word)
      other -> other
    end
  end

  defp sort_time(nil), do: 0
  defp sort_time(%DateTime{} = datetime), do: DateTime.to_unix(datetime)

  defp load_rows(team, activity) do
    Attendance
    |> join(:inner, [at], m in Member, on: m.id == at.member_id)
    |> where([at, m], at.activity_id == ^activity.id and m.team_id == ^team.id)
    |> select([at, m], %{
      id: at.id,
      member_id: m.id,
      member_name: m.name,
      status: at.status,
      started_at: at.started_at,
      finished_at: at.finished_at,
      duration_in_minutes: at.duration_in_minutes,
      replied_at: at.replied_at
    })
    |> Repo.all()
  end
end
