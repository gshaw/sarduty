defmodule App.Operation.RefreshD4HData.UpsertAttendances do
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member

  def call(d4h, team) when is_map(d4h) when is_map(team) do
    context = %{
      d4h: d4h,
      team_id: team.id,
      d4h_member_index: build_d4h_member_index(team.id),
      d4h_activity_index: build_d4h_activity_index(team.id)
    }

    fetch_and_upsert(context, 0)
  end

  defp fetch_and_upsert(context, page) do
    d4h_attendances = D4H.fetch_attendances(context.d4h, page)
    upsert_attendances(context, page, d4h_attendances)
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

  defp upsert_attendances(_context, _page, []), do: :ok

  defp upsert_attendances(context, page, d4h_attendances) do
    # IO.inspect({:attendances, :page, page, :count, Enum.count(d4h_attendances)})
    Enum.each(d4h_attendances, &upsert_attendance(context, &1))
    fetch_and_upsert(context, page + 1)
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
