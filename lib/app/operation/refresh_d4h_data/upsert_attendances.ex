defmodule App.Operation.RefreshD4HData.UpsertAttendances do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.StaleRows
  alias App.Repo

  require Logger

  def call(d4h, team, progress) when is_map(d4h) when is_map(team) do
    context = %{
      d4h_member_index: build_d4h_member_index(team.id),
      d4h_activity_index: build_d4h_activity_index(team.id)
    }

    # Raises before the delete when D4H returns fewer rows than its own total.
    {count, progress, d4h_attendance_ids} =
      D4H.reduce_attendances(d4h, {0, progress, MapSet.new()}, &upsert_page(context, &1, &2))

    delete_stale_attendances(team.id, d4h_attendance_ids)
    {count, progress}
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

  defp upsert_page(context, d4h_attendances, {total_count, progress, d4h_attendance_ids}) do
    count = Enum.count(d4h_attendances)

    d4h_attendance_ids =
      Enum.reduce(d4h_attendances, d4h_attendance_ids, fn d4h_attendance, ids ->
        upsert_attendance(context, d4h_attendance)
        MapSet.put(ids, d4h_attendance.d4h_attendance_id)
      end)

    {total_count + count, Progress.add_page(progress, count), d4h_attendance_ids}
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

  defp delete_stale_attendances(team_id, synced_d4h_ids) do
    team_member_ids = from(m in Member, where: m.team_id == ^team_id, select: m.id)

    stale_ids =
      Attendance
      |> where([a], a.member_id in subquery(team_member_ids))
      |> StaleRows.ids(:d4h_attendance_id, synced_d4h_ids)

    {count, _} = Attendance |> where([a], a.id in ^stale_ids) |> Repo.delete_all()
    Logger.info("Deleted #{count} stale attendance records for team #{team_id}")
  end
end
