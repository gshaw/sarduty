defmodule App.Operation.ProposeAttendanceChanges do
  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  # An AI agent's attendance changes for one activity, saved as a change set that waits
  # for a team admin (#216). Nothing here writes to D4H: a person reviews the set in SAR
  # Duty and ApplyChangeSet sends it, reading D4H fresh first like every other source.

  @statuses %{"attended" => "ATTENDING", "absent" => "ABSENT"}

  @doc """
  Saves the changes as a waiting change set. `requests` are maps with string keys:
  `member_id` (SAR Duty's id), `status` (`attended` or `absent`), and optional
  `starts_at`, `ends_at` (ISO 8601), and `reason`. `{:ok, change_set, problems}`, or
  `{:error, problems}` when nothing would change. `problems` are sentences about the
  requests left out.
  """
  def call(%Team{} = team, %User{} = user, activity_id, requests, summary) do
    with {:ok, activity} <- find_activity(team, activity_id) do
      attendances = activity_attendances(activity)
      members = team_members(team, requests)

      case plan(activity, attendances, members, requests) do
        {[], problems} ->
          {:error, problems}

        {rows, problems} ->
          change_set =
            ChangeSet.propose!(
              %ChangeSet{
                team_id: team.id,
                source: :agent,
                activity_id: activity.id,
                proposed_by_user_id: user.id,
                summary: summary && String.slice(summary, 0, 255)
              },
              rows
            )

          {:ok, change_set, problems}
      end
    end
  end

  defp find_activity(team, id) do
    case Repo.get_by(Activity, id: id, team_id: team.id) do
      nil -> {:error, ["No activity #{id} on this team."]}
      %Activity{deleted_at: %DateTime{}} -> {:error, ["The activity is deleted in D4H."]}
      %Activity{is_published: true} -> {:error, ["The activity is published in D4H."]}
      activity -> {:ok, activity}
    end
  end

  defp activity_attendances(activity) do
    Attendance
    |> where([a], a.activity_id == ^activity.id)
    |> Repo.all()
  end

  defp team_members(team, requests) do
    ids = for r <- requests, is_integer(r["member_id"]), do: r["member_id"]

    Member
    |> where([m], m.team_id == ^team.id and m.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  The change set rows for `requests`, and a sentence for each request left out. Pure:
  `attendances` are the activity's local rows and `members` the team's members by id.
  A member with a row gets an update. A member without one gets a create, with the
  activity's times when the request has none, since D4H needs times for a new row.
  """
  def plan(%Activity{} = activity, attendances, members, requests) do
    by_member = Map.new(attendances, &{&1.member_id, &1})

    {rows, problems, _seen} =
      Enum.reduce(
        requests,
        {[], [], MapSet.new()},
        &add_request(activity, by_member, members, &1, &2)
      )

    {Enum.reverse(rows), Enum.reverse(problems)}
  end

  defp add_request(activity, by_member, members, request, {rows, problems, seen}) do
    case plan_row(activity, by_member, members, seen, request) do
      {:ok, row} -> {[row | rows], problems, MapSet.put(seen, row.member_id)}
      {:problem, text} -> {rows, [text | problems], seen}
    end
  end

  defp plan_row(activity, by_member, members, seen, request) do
    member_id = request["member_id"]

    with {:ok, member} <- fetch_member(members, member_id),
         :ok <- check_once(seen, member),
         {:ok, status} <- fetch_status(request["status"]),
         {:ok, starts_at, ends_at} <- parse_times(request) do
      attendance = Map.get(by_member, member.id)

      case build_row(activity, attendance, member, status, starts_at, ends_at) do
        nil -> {:problem, "#{member.name} is already #{request["status"]}. Nothing to change."}
        row -> {:ok, %{row | reason: reason(request)}}
      end
    end
  end

  defp fetch_member(members, id) do
    case Map.get(members, id) do
      nil -> {:problem, "No member #{inspect(id)} on this team."}
      member -> {:ok, member}
    end
  end

  defp check_once(seen, member) do
    if MapSet.member?(seen, member.id),
      do: {:problem, "#{member.name} is in the list twice. The first one is kept."},
      else: :ok
  end

  defp fetch_status(status) do
    case Map.fetch(@statuses, status) do
      {:ok, d4h_status} -> {:ok, d4h_status}
      :error -> {:problem, "Status must be attended or absent, not #{inspect(status)}."}
    end
  end

  defp parse_times(request) do
    with {:ok, starts_at} <- parse_time(request["starts_at"]),
         {:ok, ends_at} <- parse_time(request["ends_at"]) do
      if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt,
        do: {:problem, "The end must be after the start, for member #{request["member_id"]}."},
        else: {:ok, starts_at, ends_at}
    end
  end

  defp parse_time(nil), do: {:ok, nil}

  defp parse_time(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      {:error, _} -> {:problem, "Times must be ISO 8601 with a time zone, not #{inspect(text)}."}
    end
  end

  defp parse_time(other), do: {:problem, "Times must be text, not #{inspect(other)}."}

  # No row in D4H: only attending makes sense, and D4H needs times for a new row.
  defp build_row(_activity, nil, _member, "ABSENT", _starts_at, _ends_at), do: nil

  defp build_row(activity, nil, member, "ATTENDING", starts_at, ends_at) do
    %ChangeSetRow{
      member_id: member.id,
      action: :create_attendance,
      old_value: nil,
      new_value: %{
        "status" => "ATTENDING",
        "starts_at" => ApplyChangeSet.iso(starts_at || activity.started_at),
        "ends_at" => ApplyChangeSet.iso(ends_at || activity.finished_at),
        "d4h_activity_id" => activity.d4h_activity_id,
        "d4h_member_id" => member.d4h_member_id
      }
    }
  end

  defp build_row(_activity, %Attendance{} = attendance, member, status, starts_at, ends_at) do
    # The copy holds D4H's status lowercased.
    unchanged? =
      attendance.status == String.downcase(status) and
        (starts_at == nil or starts_at == attendance.started_at) and
        (ends_at == nil or ends_at == attendance.finished_at)

    if unchanged? do
      nil
    else
      %ChangeSetRow{
        member_id: member.id,
        action: :update_attendance,
        d4h_record_id: attendance.d4h_attendance_id,
        old_value: %{
          "status" => attendance.status,
          "starts_at" => ApplyChangeSet.iso(attendance.started_at),
          "ends_at" => ApplyChangeSet.iso(attendance.finished_at)
        },
        new_value: %{
          "status" => status,
          "starts_at" => ApplyChangeSet.iso(starts_at),
          "ends_at" => ApplyChangeSet.iso(ends_at)
        }
      }
    end
  end

  defp reason(%{"reason" => reason}) when is_binary(reason) and reason != "",
    do: String.slice(reason, 0, 255)

  defp reason(_request), do: "Proposed by an AI agent"
end
