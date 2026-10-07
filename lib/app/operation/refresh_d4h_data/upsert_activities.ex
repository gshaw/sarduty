defmodule App.Operation.RefreshD4HData.UpsertActivities do
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.AttendanceLink
  alias App.Model.Coordinate
  alias App.Operation.RefreshD4HData.Progress
  alias App.Repo

  require Logger

  @activity_kinds %{"exercises" => "exercise", "events" => "event", "incidents" => "incident"}

  def call(d4h, team, d4h_tag_index, kind, progress)
      when is_map(d4h)
      when is_map(team)
      when is_map(d4h_tag_index)
      when is_binary(kind) do
    # Raises before marking anything when D4H returns fewer rows than its own total.
    {count, progress, synced_d4h_ids} =
      D4H.reduce_activities(
        d4h,
        d4h_tag_index,
        kind,
        {0, progress, MapSet.new()},
        &upsert_page(team.id, &1, &2)
      )

    mark_deleted(team, Map.fetch!(@activity_kinds, kind), synced_d4h_ids, DateTime.utc_now())
    {count, progress}
  end

  @doc """
  Which of a team's activities of one kind D4H deleted, and which it brought back, from
  the D4H ids a complete refresh saw. `activities` are the team's local rows of that kind.
  D4H leaves deleted activities out of its lists. When it lists none of a kind, nothing
  changes, since a team that had them did not lose them all at once.
  """
  def plan_deleted(activities, synced_d4h_ids) do
    if MapSet.size(synced_d4h_ids) == 0 do
      %{delete: [], restore: []}
    else
      listed? = &MapSet.member?(synced_d4h_ids, &1.d4h_activity_id)

      %{
        delete: for(a <- activities, a.deleted_at == nil, not listed?.(a), do: a.id),
        restore: for(a <- activities, a.deleted_at != nil, listed?.(a), do: a.id)
      }
    end
  end

  # Kept, not deleted: attendance links, scans, and no-shows point at them. Their open
  # attendance links close, so the door stops taking scans. Returns the plan, with local
  # ids. The sync calls this too, with the D4H ids of one kind (#163).
  def mark_deleted(team, activity_kind, synced_d4h_ids, now) do
    activities =
      Activity
      |> where([a], a.team_id == ^team.id and a.activity_kind == ^activity_kind)
      |> select([a], %{id: a.id, d4h_activity_id: a.d4h_activity_id, deleted_at: a.deleted_at})
      |> Repo.all()

    plan = plan_deleted(activities, synced_d4h_ids)
    deleted_at = DateTime.truncate(now, :second)

    Repo.transaction(fn ->
      set_deleted_at(team.id, plan.delete, deleted_at)
      set_deleted_at(team.id, plan.restore, nil)
      AttendanceLink.close_all!(team, plan.delete, now)
    end)

    Logger.info(
      "Marked #{length(plan.delete)} #{activity_kind} activities deleted and " <>
        "#{length(plan.restore)} restored for team #{team.id}"
    )

    plan
  end

  @doc "Clears the deleted mark on the team's activities that D4H lists again."
  def clear_deleted(_team, []), do: :ok

  def clear_deleted(team, d4h_activity_ids) do
    Activity
    |> where([a], a.team_id == ^team.id and a.d4h_activity_id in ^d4h_activity_ids)
    |> where([a], not is_nil(a.deleted_at))
    |> Repo.update_all(set: [deleted_at: nil, updated_at: DateTime.utc_now()])

    :ok
  end

  @doc "Saves one D4H activity for the team."
  def upsert(team_id, d4h_activity), do: upsert_activity(team_id, d4h_activity)

  defp set_deleted_at(_team_id, [], _deleted_at), do: :ok

  defp set_deleted_at(team_id, ids, deleted_at) do
    Activity
    |> where([a], a.team_id == ^team_id and a.id in ^ids)
    |> Repo.update_all(set: [deleted_at: deleted_at, updated_at: DateTime.utc_now()])
  end

  defp upsert_page(team_id, d4h_activities, {total_count, progress, synced_d4h_ids}) do
    count = Enum.count(d4h_activities)
    Enum.each(d4h_activities, &upsert_activity(team_id, &1))
    synced_d4h_ids = Enum.into(d4h_activities, synced_d4h_ids, & &1.d4h_activity_id)
    {total_count + count, Progress.add_page(progress, count), synced_d4h_ids}
  end

  defp upsert_activity(team_id, d4h_activity) do
    params = %{
      team_id: team_id,
      d4h_activity_id: d4h_activity.d4h_activity_id,
      ref_id: d4h_activity.ref_id,
      tracking_number: d4h_activity.tracking_number,
      is_published: d4h_activity.is_published,
      title: d4h_activity.title,
      description: d4h_activity.description,
      address: d4h_activity.address,
      coordinate: Coordinate.to_string(d4h_activity.coordinate, 5),
      activity_kind: d4h_activity.activity_kind,
      hours_kind: nil,
      started_at: d4h_activity.started_at,
      finished_at: d4h_activity.finished_at,
      tags: d4h_activity.tags
    }

    activity = Activity.get_by(team_id: team_id, d4h_activity_id: d4h_activity.d4h_activity_id)

    if activity do
      Activity.update!(activity, params)
    else
      Activity.insert!(params)
    end
  end
end
