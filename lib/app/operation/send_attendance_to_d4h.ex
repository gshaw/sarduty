defmodule App.Operation.SendAttendanceToD4H do
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.AttendanceScan
  alias App.Model.Member
  alias App.Model.NoShow
  alias App.Model.Team
  alias App.Operation.BuildAttendanceTimes

  # Sends the door's attendance to D4H. `preview` reads the activity's D4H attendance
  # and plans the changes for a team admin to review; `call` reads it again, plans
  # again, and makes the changes the admin kept. Planning from a fresh read matters:
  # D4H accepts a second row for a member and counts their hours twice, so a member
  # with a row is always changed, never added. Writes don't retry; a person is watching
  # and can send again, which plans from what D4H has by then.

  @doc """
  The changes to make, one per member, from the door's `times` and D4H's attendance
  `rows` now. `members` are the team's members, to match D4H's rows to. Each change is
  a map with `:key`, `:member`, `:action`, `:d4h_attendance_id`, `:arrived_at`,
  `:left_at`, `:status` (D4H's now, or nil), `:selected` (whether it starts checked),
  and `:notes`. Actions:

  - `:update`: mark the member's row attending with the door's times.
  - `:create`: add a row for a member D4H has none for, as a walk-in.
  - `:absent`: mark a row with no scans absent. Checked for members who signed up
    (requested), unchecked for members already attending in D4H, since someone may
    have marked them by hand.
  - `:unchanged`: D4H already has these times.
  - `:blocked`: the times can't be sent until they're fixed at the door.
  """
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
        row.status in ["requested", "attending"],
        member <- List.wrap(members_by_d4h_id[row.d4h_member_id]) do
      attending = row.status == "attending"
      notes = if attending, do: [:attending_without_scan], else: []
      change(member, :absent, row, selected: not attending, notes: notes)
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
  def no_show?(%{action: :absent, status: "requested"}), do: true
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
  Makes the kept changes, named by `keys`, from a fresh plan. When they all go
  through, it closes the activity's attendance links. `{:ok, results}` with `{change, :ok | {:error, message}}`
  for each change sent; `{:error, :published}` when D4H has published the activity;
  otherwise the error from `preview/2`.
  """
  def call(%Team{} = team, %Activity{} = activity, keys, now) do
    keys = MapSet.new(keys)

    case preview(team, activity) do
      {:ok, %{published: false, changes: changes}} ->
        d4h = D4H.build_context_from_team(team)

        results =
          for change <- changes, sendable?(change), change.key in keys do
            {change, write(d4h, activity, change)}
          end

        # A failed change keeps the link open, so the door can still fix times.
        if Enum.all?(results, &match?({_change, :ok}, &1)),
          do: AttendanceLink.close_all!(team, activity, now)

        {:ok, results}

      {:ok, %{published: true}} ->
        {:error, :published}

      error ->
        error
    end
  end

  defp write(d4h, activity, change) do
    result =
      case change.action do
        :update ->
          D4H.set_attendance(
            d4h,
            change.d4h_attendance_id,
            "ATTENDING",
            change.arrived_at,
            change.left_at
          )

        :create ->
          D4H.create_attendance(
            d4h,
            activity.d4h_activity_id,
            change.member.d4h_member_id,
            change.arrived_at,
            change.left_at
          )

        :absent ->
          D4H.set_attendance(d4h, change.d4h_attendance_id, "ABSENT", nil, nil)
      end

    case result do
      {:ok, _info} ->
        if no_show?(change), do: NoShow.record!(activity, change.member)
        :ok

      {:error, error} ->
        {:error, failure_text(error)}
    end
  end

  @doc """
  What to show for a failed write. D4H answers 400 or 404 when the activity or the
  attendance row is gone, so that says so before D4H's own text.
  """
  def failure_text(%D4H.Error{status: status} = error) when status in [400, 404],
    do: "The activity may have been deleted or changed in D4H. #{Exception.message(error)}"

  def failure_text(error), do: Exception.message(error)
end
