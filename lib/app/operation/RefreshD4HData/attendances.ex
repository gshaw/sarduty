defmodule App.Operation.RefreshD4HData.Attendances do
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member

  def call(d4h, team_id) do
    context = %{
      d4h: d4h,
      team_id: team_id,
      d4h_member_index: build_d4h_member_index(team_id),
      d4h_activity_index: build_d4h_activity_index(team_id)
    }

    d4h_attendances = D4H.fetch_attendances(d4h)
    upsert_attendances(context, d4h_attendances)
    :ok
  end

  defp build_d4h_activity_index(team_id) do
    team_id
    |> Activity.get_all()
    |> Enum.map(fn r -> {r.d4h_activity_id, r.id} end)
    |> Map.new()
  end

  defp build_d4h_member_index(team_id) do
    team_id
    |> Member.get_all()
    |> Enum.map(fn r -> {r.d4h_member_id, r.id} end)
    |> Map.new()
  end

  defp upsert_attendances(context, d4h_attendances) do
    Enum.each(d4h_attendances, fn d4h_attendance ->
      upsert_attendance(context, d4h_attendance)
    end)
  end

  defp upsert_attendance(context, d4h_attendance) do
    member_id = context.d4h_member_index[d4h_attendance.d4h_member_id]
    activity_id = context.d4h_activity_index[d4h_attendance.d4h_activity_id]
    upsert_attendance(member_id, activity_id, d4h_attendance)
  end

  defp upsert_attendance(nil, _activity_id, _d4h_attendance), do: :skip
  defp upsert_attendance(_member_id, nil, _d4h_attendance), do: :skip

  defp upsert_attendance(member_id, activity_id, d4h_attendance) do
    params = %{
      member_id: member_id,
      activity_id: activity_id,
      d4h_attendance_id: d4h_attendance.d4h_attendance_id,
      duration_in_minutes: d4h_attendance.duration_in_minutes,
      started_at: d4h_attendance.started_at,
      finished_at: d4h_attendance.finished_at,
      status: d4h_attendance.status
    }

    attendance =
      Attendance.get_by(
        member_id: member_id,
        activity_id: activity_id,
        d4h_attendance_id: d4h_attendance.d4h_attendance_id
      )

    if attendance do
      Attendance.update!(attendance, params)
    else
      Attendance.insert!(params)
    end
  end
end
