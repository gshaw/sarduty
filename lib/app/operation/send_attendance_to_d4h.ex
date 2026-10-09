defmodule App.Operation.SendAttendanceToD4H do
  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.NoShow
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.BuildAttendanceTimes

  # Sends the door's attendance to D4H. `preview` reads the activity's D4H attendance
  # and plans the changes for a team admin to review; `call` reads it again, plans
  # again, and sends the changes the admin kept as a change set (#174). Planning from a
  # fresh read matters: D4H accepts a second row for a member and counts their hours
  # twice, so a member with a row is always changed, never added. Writes don't retry; a person is watching
  # and can send again, which plans from what D4H has by then.

  @doc """
  The changes to make, one per member, from the door's `times` and D4H's attendance
  `rows` now. `members` are the team's members, to match D4H's rows to. Each change is
  a map with `:key`, `:member`, `:action`, `:d4h_attendance_id`, `:arrived_at`,
  `:left_at`, `:status` (D4H's now, or nil), `:selected` (whether it starts checked),
  and `:notes`. Actions:

  - `:update`: mark the member's row attending with the door's times.
  - `:create`: add a row for a member D4H has none for, as a walk-in.
  - `:absent`: mark a member who signed up (attending) and has no scans absent, checked,
    with a note: D4H's attending also means marked there by hand. With no scans at all
    the door wasn't used, so nobody is offered. A requested row is an invite nobody
    replied to, so it's left alone.
  - `:unchanged`: D4H already has these times.
  - `:blocked`: the times can't be sent until they're fixed at the door.
  """
  def plan([], _rows, _members), do: []

  def plan(times, rows, members) do
    rows_by_d4h_member_id = rows |> Enum.reverse() |> Map.new(&{&1.d4h_member_id, &1})

    scanned = Enum.map(times, &plan_scanned(&1, row_for(rows_by_d4h_member_id, &1.member)))
    scanned_d4h_ids = MapSet.new(times, & &1.member.d4h_member_id)

    not_scanned =
      rows_by_d4h_member_id
      |> Map.drop(MapSet.to_list(scanned_d4h_ids))
      |> Map.values()
      |> plan_not_scanned(members)

    Enum.sort_by(scanned ++ not_scanned, &sort_key/1)
  end

  defp row_for(rows_by_d4h_member_id, member), do: rows_by_d4h_member_id[member.d4h_member_id]

  defp plan_not_scanned(rows, members) do
    members_by_d4h_id = Map.new(members, &{&1.d4h_member_id, &1})

    for row <- rows,
        row.status == "attending",
        member <- List.wrap(members_by_d4h_id[row.d4h_member_id]) do
      change(member, :absent, row, selected: true, notes: [:signed_up_without_scan])
    end
  end

  defp sort_key(change), do: {action_order(change.action), String.downcase(change.member.name)}

  defp plan_scanned(time, row) do
    times = [arrived_at: time.arrived_at, left_at: time.left_at, notes: time.notes]

    cond do
      not BuildAttendanceTimes.sendable?(time) ->
        change(time.member, :blocked, row, [selected: false] ++ times)

      row == nil ->
        change(time.member, :create, nil, [selected: true] ++ times)

      row.status == "attending" and same_minute?(row.started_at, time.arrived_at) and
          same_minute?(row.finished_at, time.left_at) ->
        change(time.member, :unchanged, row, [selected: false] ++ times)

      true ->
        change(time.member, :update, row, [selected: true] ++ times)
    end
  end

  defp change(member, action, row, opts) do
    %{
      key: "member-#{member.id}",
      member: member,
      action: action,
      d4h_attendance_id: row && row.d4h_attendance_id,
      status: row && row.status,
      arrived_at: opts[:arrived_at],
      left_at: opts[:left_at],
      selected: Keyword.fetch!(opts, :selected),
      notes: opts[:notes] || []
    }
  end

  defp same_minute?(nil, _time), do: false
  defp same_minute?(d4h_time, time), do: abs(DateTime.diff(d4h_time, time, :second)) < 60

  defp action_order(:blocked), do: 0
  defp action_order(:update), do: 1
  defp action_order(:create), do: 2
  defp action_order(:absent), do: 3
  defp action_order(:unchanged), do: 4

  @doc "Whether a change marks a member who signed up and didn't come."
  def no_show?(%{action: :absent, status: "attending"}), do: true
  def no_show?(_change), do: false

  @doc "Whether a change writes to D4H when it's kept."
  def sendable?(%{action: action}), do: action in [:update, :create, :absent]

  @doc """
  Reads D4H and plans. `{:ok, %{published: boolean, changes: [change]}}`, or
  `{:error, %D4H.Error{}}` when D4H can't be read, `{:error, :no_team_key}`, or
  `{:error, :deleted}` for an activity deleted in D4H.
  """
  def preview(%Team{}, %Activity{deleted_at: %DateTime{}}), do: {:error, :deleted}
  def preview(%Team{d4h_access_key: nil}, %Activity{}), do: {:error, :no_team_key}

  def preview(%Team{} = team, %Activity{team_id: team_id} = activity)
      when team_id == team.id do
    d4h = D4H.build_context_from_team(team)

    with {:ok, published} <-
           D4H.fetch_activity_published(d4h, activity.d4h_activity_id, activity.activity_kind),
         {:ok, rows} <- D4H.fetch_attendance_infos(d4h, activity.d4h_activity_id) do
      times = BuildAttendanceTimes.call(activity, AttendanceScan.get_all(activity))
      {:ok, %{published: published, changes: plan(times, rows, Member.get_all(team.id))}}
    end
  end

  @doc """
  Makes the kept changes, named by `keys`, from a fresh plan, as a change set applied
  by `user`. When they all go through, it closes the activity's attendance links.
  `{:ok, results}` with `{change, :ok | {:error, message}}` for each change sent;
  `{:error, :published}` when D4H has published the activity; otherwise the error from
  `preview/2`.
  """
  def call(%Team{} = team, %Activity{} = activity, %User{} = user, keys, now) do
    keys = MapSet.new(keys)

    case preview(team, activity) do
      {:ok, %{published: false, changes: changes}} ->
        kept = for change <- changes, sendable?(change), change.key in keys, do: change
        send_kept(team, activity, user, kept, now)

      {:ok, %{published: true}} ->
        {:error, :published}

      error ->
        error
    end
  end

  defp send_kept(team, activity, user, kept, now) do
    with {:ok, results} <- apply_changes(team, activity, user, kept, now) do
      # A failed change keeps the link open, so the door can still fix times.
      if Enum.all?(results, &match?({_change, :ok}, &1)),
        do: AttendanceLink.close_all!(team, activity, now)

      {:ok, results}
    end
  end

  defp apply_changes(_team, _activity, _user, [], _now), do: {:ok, []}

  defp apply_changes(team, activity, user, changes, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :door,
          activity_id: activity.id,
          proposed_by_user_id: user.id
        },
        Enum.map(changes, &change_set_row(activity, &1))
      )

    with {:ok, rows} <- ApplyChangeSet.call(team, change_set, user, now) do
      {:ok, Enum.zip_with(changes, rows, &result(activity, &1, &2))}
    end
  end

  defp result(activity, change, %ChangeSetRow{status: :applied}) do
    if no_show?(change), do: NoShow.record!(activity, change.member)
    {change, :ok}
  end

  defp result(_activity, change, %ChangeSetRow{error: error}), do: {change, {:error, error}}

  @doc "The change set row for a change."
  def change_set_row(activity, change) do
    row = %ChangeSetRow{member_id: change.member.id, reason: reason(change)}

    case change.action do
      :update ->
        %{
          row
          | action: :update_attendance,
            d4h_record_id: change.d4h_attendance_id,
            old_value: %{"status" => change.status},
            new_value: attending(change)
        }

      :create ->
        %{
          row
          | action: :create_attendance,
            new_value:
              change
              |> attending()
              |> Map.merge(%{
                "d4h_activity_id" => activity.d4h_activity_id,
                "d4h_member_id" => change.member.d4h_member_id
              })
        }

      :absent ->
        %{
          row
          | action: :update_attendance,
            d4h_record_id: change.d4h_attendance_id,
            old_value: %{"status" => change.status},
            new_value: %{"status" => "ABSENT"}
        }
    end
  end

  defp attending(change) do
    %{
      "status" => "ATTENDING",
      "starts_at" => ApplyChangeSet.iso(change.arrived_at),
      "ends_at" => ApplyChangeSet.iso(change.left_at)
    }
  end

  defp reason(%{action: :update}), do: "Scanned at the door"
  defp reason(%{action: :create}), do: "Scanned at the door, not signed up"
  defp reason(%{action: :absent}), do: "Signed up, not scanned at the door"
end
