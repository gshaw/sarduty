defmodule App.Operation.RefreshD4HData.Activities do
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate

  def call(d4h, team_id) do
    d4h_activities = D4H.fetch_activities(d4h)
    upsert_activities(team_id, d4h_activities)
    :ok
  end

  defp upsert_activities(team_id, d4h_activities) do
    Enum.each(d4h_activities, fn d4h_activity ->
      upsert_activity(team_id, d4h_activity)
    end)
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
