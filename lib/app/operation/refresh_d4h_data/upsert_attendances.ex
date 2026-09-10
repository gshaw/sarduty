defmodule App.Operation.RefreshD4HData.UpsertAttendances do
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Operation.RefreshD4HData.Progress

  def call(d4h, team, progress) when is_map(d4h) when is_map(team) do
    context = %{
      d4h: d4h,
      team_id: team.id,
      d4h_member_index: build_d4h_member_index(team.id),
      d4h_activity_index: build_d4h_activity_index(team.id),
      progress: progress,
      total_count: 0,
      d4h_attendance_ids: MapSet.new()
    }

    {count, progress, d4h_attendance_ids} = fetch_and_upsert(context, 0)
    delete_stale_attendances(team.id, d4h_attendance_ids)
    {count, progress}
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

  defp upsert_attendances(context, _page, []) do
    {context.total_count, context.progress, context.d4h_attendance_ids}
  end

  defp upsert_attendances(context, page, d4h_attendances) do
    count = Enum.count(d4h_attendances)

    d4h_attendance_ids =
      Enum.reduce(d4h_attendances, context.d4h_attendance_ids, fn d4h_attendance, ids ->
        upsert_attendance(context, d4h_attendance)
        MapSet.put(ids, d4h_attendance.d4h_attendance_id)
      end)

    progress = Progress.add_page(context.progress, count)

    context = %{
      context
      | progress: progress,
        total_count: context.total_count + count,
        d4h_attendance_ids: d4h_attendance_ids
    }

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

  defp delete_stale_attendances(team_id, synced_d4h_ids) do
    import Ecto.Query

    # Get all d4h_attendance_ids for this team
    all_local_d4h_ids =
      Attendance
      |> join(:inner, [a], m in Member, on: a.member_id == m.id)
      |> where([a, m], m.team_id == ^team_id)
      |> select([a], a.d4h_attendance_id)
      |> App.Repo.all()
      |> MapSet.new()

    # Find stale d4h_attendance_ids (in local DB but not in D4H API response)
    stale_d4h_ids = MapSet.difference(all_local_d4h_ids, synced_d4h_ids)

    {count, _} =
      Attendance
      |> where([a], a.d4h_attendance_id in ^MapSet.to_list(stale_d4h_ids))
      |> App.Repo.delete_all()

    require Logger
    Logger.info("Deleted #{count} stale attendance records for team #{team_id}")

    :ok
  end
end
