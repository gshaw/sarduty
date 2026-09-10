defmodule App.Operation.RefreshD4HData.UpsertActivities do
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Operation.RefreshD4HData.Progress

  def call(d4h, team, d4h_tag_index, kind, progress)
      when is_map(d4h)
      when is_map(team)
      when is_map(d4h_tag_index)
      when is_binary(kind) do
    D4H.reduce_activities(d4h, d4h_tag_index, kind, {0, progress}, &upsert_page(team.id, &1, &2))
  end

  defp upsert_page(team_id, d4h_activities, {total_count, progress}) do
    count = Enum.count(d4h_activities)
    Enum.each(d4h_activities, &upsert_activity(team_id, &1))
    {total_count + count, Progress.add_page(progress, count)}
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
