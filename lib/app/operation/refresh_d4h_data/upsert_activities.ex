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
    context = %{
      d4h: d4h,
      team_id: team.id,
      d4h_tag_index: d4h_tag_index,
      kind: kind,
      progress: progress,
      total_count: 0
    }

    fetch_and_upsert(context, 0)
  end

  defp fetch_and_upsert(context, page) do
    d4h_activities = D4H.fetch_activities(context.d4h, context.d4h_tag_index, context.kind, page)
    upsert_activities(context, page, d4h_activities)
  end

  defp upsert_activities(context, _page, []) do
    {context.total_count, context.progress}
  end

  defp upsert_activities(context, page, d4h_activities) do
    count = Enum.count(d4h_activities)

    Enum.each(d4h_activities, &upsert_activity(context.team_id, &1))

    progress = Progress.add_page(context.progress, count)
    context = %{context | progress: progress, total_count: context.total_count + count}
    fetch_and_upsert(context, page + 1)
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
