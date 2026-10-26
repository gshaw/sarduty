defmodule App.Operation.ProposeAttendanceChanges do
  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.ChoreEvent
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  # An AI agent's attendance changes for one activity, saved as a change set that waits
  # for a team admin (#216, #595). Nothing here writes to D4H: a person reviews the set in
  # SAR Duty and ApplyChangeSet sends it, reading D4H fresh first like every other source.

  # The statuses an agent gives, in the glossary's words, which change when the activity
  # starts, and the D4H status each sets.
  @before_start %{
    "no_reply" => "REQUESTED",
    "signed_up" => "ATTENDING",
    "cant_make_it" => "ABSENT"
  }
  @after_start %{"attended" => "ATTENDING", "absent" => "ABSENT"}

  @doc """
  Saves the changes as a waiting change set. `requests` are maps with string keys:
  `attendance_id` (SAR Duty's id of a row on the activity) or `member_id`, `status`, and
  optional `starts_at`, `ends_at` (ISO 8601), and `reason`. `{:ok, change_set, problems}`,
  or `{:error, problems}` when nothing would change. `problems` are sentences about the
  requests left out.
  """
  def call(%Team{} = team, %User{} = user, activity_id, requests, summary, now) do
    with {:ok, activity} <- find_activity(team, activity_id) do
      attendances = activity_attendances(team, activity)
      members = team_members(team, requests, attendances)

      case plan(activity, attendances, members, requests, now) do
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
      nil ->
        {:error, ["No activity #{inspect(id)} on this team."]}

      %Activity{deleted_at: %DateTime{}} ->
        {:error, ["The activity is deleted."]}

      %Activity{is_published: true} ->
        {:error, ["The activity is published."]}

      activity ->
        if ChoreEvent.put_chore_minutes(activity).chore_minutes,
          do: {:error, ["It is a chore activity. SAR Duty rebuilds its attendance from chores."]},
          else: {:ok, activity}
    end
  end

  defp activity_attendances(team, activity) do
    Attendance
    |> join(:inner, [a], m in Member, on: m.id == a.member_id)
    |> where([a, m], a.activity_id == ^activity.id and m.team_id == ^team.id)
    |> Repo.all()
  end

  # The members the requests name, and every member with a row on the activity.
  defp team_members(team, requests, attendances) do
    ids =
      for(r <- requests, is_integer(r["member_id"]), do: r["member_id"]) ++
        Enum.map(attendances, & &1.member_id)

    Member
    |> where([m], m.team_id == ^team.id and m.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  The change set rows for `requests`, and a sentence for each request left out. Pure:
  `attendances` are the activity's local rows and `members` the team's members by id,
  everyone with a row among them.

  An `attendance_id` names a row. A `member_id` names the member's row when they have
  one, and adds a row when they have none: as no reply, or with the activity's times
  when the request has none, since D4H needs times for a new row. Before the activity
  starts the statuses are no_reply, signed_up, and cant_make_it; once it starts, attended
  and absent. remove takes a row off at any time.
  """
  def plan(%Activity{} = activity, attendances, members, requests, now) do
    context = %{
      activity: activity,
      members: members,
      by_id: Map.new(attendances, &{&1.id, &1}),
      by_member: Enum.group_by(attendances, & &1.member_id),
      started?: not DateTime.after?(activity.started_at, now)
    }

    {planned, problems, _seen} =
      Enum.reduce(requests, {[], [], MapSet.new()}, &add_request(context, &1, &2))

    {Enum.reverse(planned), Enum.reverse(problems)}
  end

  defp add_request(context, request, {planned, problems, seen}) do
    case plan_row(context, seen, request) do
      {:ok, row, key} -> {[row | planned], problems, MapSet.put(seen, key)}
      {:problem, text} -> {planned, [text | problems], seen}
    end
  end

  defp plan_row(context, seen, request) do
    with {:ok, member, attendance} <- target(context, request),
         key = row_key(member, attendance),
         :ok <- check_once(seen, key, member),
         {:ok, status} <- fetch_status(request["status"], context.started?),
         {:ok, starts_at, ends_at} <- parse_times(request) do
      context.activity
      |> build_row(attendance, member, status, starts_at, ends_at)
      |> with_reason(request, key)
    end
  end

  defp row_key(_member, %Attendance{id: id}), do: {:row, id}
  defp row_key(member, nil), do: {:member, member.id}

  defp with_reason({:problem, text}, _request, _key), do: {:problem, text}
  defp with_reason(row, request, key), do: {:ok, %{row | reason: reason(request)}, key}

  # The member and the row a request names: the row by its id, or the member's only row.
  defp target(context, %{"attendance_id" => id}) when is_integer(id) do
    case Map.get(context.by_id, id) do
      nil -> {:problem, "No attendance #{id} on this activity."}
      attendance -> {:ok, Map.fetch!(context.members, attendance.member_id), attendance}
    end
  end

  defp target(context, %{"member_id" => id}) do
    case {Map.get(context.members, id), Map.get(context.by_member, id, [])} do
      {nil, _rows} ->
        {:problem, "No member #{inspect(id)} on this team."}

      {member, [_first, _second | _rest]} ->
        {:problem, "#{member.name} has 2 rows on this activity. Name one by its attendance_id."}

      {member, rows} ->
        {:ok, member, List.first(rows)}
    end
  end

  defp target(_context, _request),
    do: {:problem, "Give each change an attendance_id or a member_id."}

  defp check_once(seen, key, member) do
    if MapSet.member?(seen, key),
      do: {:problem, "#{member.name} is in the list twice. The first one is kept."},
      else: :ok
  end

  defp fetch_status("remove", _started?), do: {:ok, :remove}

  defp fetch_status(status, true) do
    case Map.fetch(@after_start, status) do
      {:ok, d4h_status} ->
        {:ok, {status, d4h_status}}

      :error ->
        {:problem,
         "The activity has started. Give attended, absent, or remove, not #{inspect(status)}."}
    end
  end

  defp fetch_status(status, false) do
    case Map.fetch(@before_start, status) do
      {:ok, d4h_status} ->
        {:ok, {status, d4h_status}}

      :error ->
        {:problem,
         "The activity has not started. Give no_reply, signed_up, cant_make_it, or remove, not #{inspect(status)}."}
    end
  end

  defp parse_times(request) do
    with {:ok, starts_at} <- parse_time(request["starts_at"]),
         {:ok, ends_at} <- parse_time(request["ends_at"]) do
      if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt,
        do: {:problem, "The end must be after the start, for #{describe(request)}."},
        else: {:ok, starts_at, ends_at}
    end
  end

  defp describe(%{"attendance_id" => id}) when is_integer(id), do: "attendance #{id}"
  defp describe(request), do: "member #{request["member_id"]}"

  defp parse_time(nil), do: {:ok, nil}

  defp parse_time(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      {:error, _} -> {:problem, "Times must be ISO 8601 with a time zone, not #{inspect(text)}."}
    end
  end

  defp parse_time(other), do: {:problem, "Times must be text, not #{inspect(other)}."}

  defp build_row(_activity, nil, member, :remove, _starts_at, _ends_at),
    do: {:problem, "#{member.name} has no row on this activity to remove."}

  defp build_row(_activity, %Attendance{} = attendance, member, :remove, _starts_at, _ends_at) do
    %ChangeSetRow{
      member_id: member.id,
      action: :delete_attendance,
      d4h_record_id: attendance.d4h_attendance_id,
      old_value: old_value(attendance),
      new_value: %{}
    }
  end

  # No row: D4H takes a new row only as no reply or attending, and needs its times.
  defp build_row(_activity, nil, member, {word, "ABSENT"}, _starts_at, _ends_at),
    do: {:problem, "#{member.name} has no row on this activity to mark #{word}."}

  defp build_row(activity, nil, member, {_word, d4h_status}, starts_at, ends_at) do
    %ChangeSetRow{
      member_id: member.id,
      action: :create_attendance,
      old_value: nil,
      new_value: %{
        "status" => d4h_status,
        "starts_at" => ApplyChangeSet.iso(starts_at || activity.started_at),
        "ends_at" => ApplyChangeSet.iso(ends_at || activity.finished_at),
        "d4h_activity_id" => activity.d4h_activity_id,
        "d4h_member_id" => member.d4h_member_id
      }
    }
  end

  defp build_row(
         _activity,
         %Attendance{},
         member,
         {"no_reply", _d4h_status},
         _starts_at,
         _ends_at
       ),
       do: {:problem, "#{member.name} has replied already, and a reply cannot be taken back."}

  defp build_row(
         _activity,
         %Attendance{} = attendance,
         member,
         {word, status},
         starts_at,
         ends_at
       ) do
    # The copy holds D4H's status lowercased.
    unchanged? =
      attendance.status == String.downcase(status) and
        (starts_at == nil or starts_at == attendance.started_at) and
        (ends_at == nil or ends_at == attendance.finished_at)

    if unchanged? do
      {:problem,
       "#{member.name} is already #{String.replace(word, "_", " ")}. Nothing to change."}
    else
      %ChangeSetRow{
        member_id: member.id,
        action: :update_attendance,
        d4h_record_id: attendance.d4h_attendance_id,
        old_value: old_value(attendance),
        new_value: %{
          "status" => status,
          "starts_at" => ApplyChangeSet.iso(starts_at),
          "ends_at" => ApplyChangeSet.iso(ends_at)
        }
      }
    end
  end

  defp old_value(%Attendance{} = attendance) do
    %{
      "status" => attendance.status,
      "starts_at" => ApplyChangeSet.iso(attendance.started_at),
      "ends_at" => ApplyChangeSet.iso(attendance.finished_at)
    }
  end

  defp reason(%{"reason" => reason}) when is_binary(reason) and reason != "",
    do: String.slice(reason, 0, 255)

  defp reason(_request), do: "Proposed by an AI agent"
end
