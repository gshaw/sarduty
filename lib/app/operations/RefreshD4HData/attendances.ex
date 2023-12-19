defmodule App.Operation.RefreshD4HData.Attendances do
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member

  def call(d4h, team_id) do
    context = %{
      d4h: d4h,
      team_id: team_id,
      member_index: build_member_index(team_id),
      activity_index: build_activity_index(team_id),
      limit: 750
    }

    d4h_attendances = D4H.fetch_attendances(d4h, params: [limit: context.limit])
    upsert_attendances(context, 0, d4h_attendances)
    :ok
  end

  defp build_activity_index(team_id) do
    Activity.get_all(team_id) |> Enum.map(fn m -> {m.d4h_id, m.id} end) |> Map.new()
  end

  defp build_member_index(team_id) do
    Member.get_all(team_id) |> Enum.map(fn m -> {m.d4h_id, m.id} end) |> Map.new()
  end

  defp upsert_attendances(_context, _offset, []), do: :ok

  defp upsert_attendances(context, offset, d4h_attendances) do
    Enum.each(d4h_attendances, fn d4h_attendance ->
      upsert_attendance(context, d4h_attendance)
    end)

    d4h_attendances =
      D4H.fetch_attendances(context.d4h, params: [offset: offset, limit: context.limit])

    upsert_attendances(context, offset + context.limit, d4h_attendances)
  end

  defp upsert_attendance(context, d4h_attendance) do
    member_id = context.member_index[d4h_attendance.member_id]
    activity_id = context.activity_index[d4h_attendance.activity_id]
    upsert_attendance(member_id, activity_id, d4h_attendance)
  end

  defp upsert_attendance(nil, _activity_id, _d4h_attendance), do: :skip
  defp upsert_attendance(_member_id, nil, _d4h_attendance), do: :skip

  defp upsert_attendance(member_id, activity_id, d4h_attendance) do
    attendance =
      Attendance.get_by(
        member_id: member_id,
        activity_id: activity_id,
        d4h_id: d4h_attendance.attendance_id
      )

    if attendance do
      Attendance.update!(attendance, %{
        duration_in_minutes: d4h_attendance.duration_in_minutes,
        started_at: d4h_attendance.started_at,
        finished_at: d4h_attendance.finished_at,
        status: d4h_attendance.status
      })
    else
      Attendance.insert!(%{
        member_id: member_id,
        activity_id: activity_id,
        d4h_id: d4h_attendance.attendance_id,
        duration_in_minutes: d4h_attendance.duration_in_minutes,
        started_at: d4h_attendance.started_at,
        finished_at: d4h_attendance.finished_at,
        status: d4h_attendance.status
      })
    end
  end
end
