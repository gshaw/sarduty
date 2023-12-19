defmodule App.Operation.BuildMilesageReport do
  alias App.Adapter.D4H
  alias App.Adapter.Mapbox

  def call(d4h, activity_id) do
    {:ok, team} = D4H.fetch_team(d4h)
    activity = D4H.fetch_activity(d4h, activity_id)
    team_members = D4H.fetch_team_members(d4h)
    attendance_records = D4H.fetch_activity_attendance(d4h, activity_id, team_members)

    mapbox = Mapbox.build_context()
    activity_coordinate = activity.coordinate
    yard_coordinate = team.coordinate

    attendees =
      attendance_records
      |> Enum.filter(&(&1.status == "attending"))
      |> Task.async_stream(fn attending ->
        address = attending.member.address

        {coordinate, activity_distance, activity_duration, yard_distance, yard_duration} =
          case Mapbox.fetch_coordinate(mapbox, address, activity_coordinate) do
            {:ok, coordinate} ->
              {activity_distance, activity_duration} =
                case Mapbox.fetch_driving_info(mapbox, activity_coordinate, coordinate) do
                  {:ok, distance, duration} -> {distance, duration}
                  {:error, _} -> {"unknown", "unknown"}
                end

              {yard_distance, yard_duration} =
                case Mapbox.fetch_driving_info(mapbox, yard_coordinate, coordinate) do
                  {:ok, distance, duration} -> {distance, duration}
                  {:error, _} -> {"unknown", "unknown"}
                end

              {coordinate, activity_distance, activity_duration, yard_distance, yard_duration}

            {:error, reason, _response} ->
              {reason, nil, nil, nil, nil}
          end

        %{
          member_id: attending.member.d4h_member_id,
          name: attending.member.name,
          address: address,
          coordinate: coordinate,
          activity_km: build_round_trip_distance(activity_distance),
          activity_hours: build_round_trip_duration(activity_duration),
          yard_km: build_round_trip_distance(yard_distance),
          yard_hours: build_round_trip_duration(yard_duration)
        }
      end)
      |> Enum.map(fn {:ok, a} -> a end)
      |> Enum.sort(&(&1.name < &2.name))

    {yard_to_activity_distance, yard_to_activity_duration} =
      case Mapbox.fetch_driving_info(mapbox, yard_coordinate, activity_coordinate) do
        {:ok, distance, duration} -> {distance, duration}
        {:error, _} -> {"unknown", "unknown"}
      end

    %{
      attendees: attendees,
      yard_to_activity_km: build_round_trip_distance(yard_to_activity_distance),
      yard_to_activity_hours: build_round_trip_duration(yard_to_activity_duration)
    }
  end

  defp build_round_trip_distance(nil), do: nil

  defp build_round_trip_distance(distance) do
    round(distance / 1000 * 2)
  end

  defp build_round_trip_duration(nil), do: nil

  defp build_round_trip_duration(duration) do
    Float.round(duration / 3600 * 2, 1)
  end
end
