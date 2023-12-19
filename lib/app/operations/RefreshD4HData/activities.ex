defmodule App.Operation.RefreshD4HData.Activities do
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate

  def call(d4h, team_id) do
    limit = 750
    d4h_activities = D4H.fetch_activites(d4h, params: [limit: limit])
    upsert_activites(d4h, team_id, 0, limit, d4h_activities)
    :ok
  end

  defp upsert_activites(_d4h, _team_id, _offset, _limit, []), do: :ok

  defp upsert_activites(d4h, team_id, offset, limit, d4h_activities) do
    Enum.each(d4h_activities, fn d4h_activity ->
      upsert_activity(team_id, d4h_activity)
    end)

    d4h_activities = D4H.fetch_activites(d4h, params: [offset: offset, limit: limit])
    upsert_activites(d4h, team_id, offset + limit, limit, d4h_activities)
  end

  defp upsert_activity(team_id, d4h_activity) do
    params = %{
      team_id: team_id,
      d4h_activity_id: d4h_activity.d4h_activity_id,
      ref_id: d4h_activity.ref_id,
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
