defmodule App.Operation.BuildMilesageReport do
  alias App.Adapter.D4H
  alias App.Adapter.Mapbox

  def call(d4h, activity_id) do
    :timer.sleep(500)

    activity = D4H.fetch_activity(d4h, activity_id)
    team_members = D4H.fetch_team_members(d4h)
    attendance_records = D4H.fetch_activity_attendance(d4h, activity_id, team_members)

    mapbox = Mapbox.build_context()
    activity_coordinate = activity.coordinate

    attendance_records
    |> Enum.filter(&(&1.status == "attending"))
    |> Task.async_stream(fn attending ->
      address = attending.member.address

      {coordinate, distance, duration} =
        case Mapbox.fetch_coordinate(mapbox, address, activity_coordinate) do
          {:ok, coordinate} ->
            {distance, duration} =
              case Mapbox.fetch_driving_info(mapbox, activity_coordinate, coordinate) do
                {:ok, distance, duration} -> {distance, duration}
                {:error, _} -> {"unknown", "unknown"}
              end

            {coordinate, distance, duration}

          {:error, response} ->
            {"status:#{response.status}", nil, nil}
        end

      %{
        member_id: attending.member.member_id,
        name: attending.member.name,
        address: address,
        coordinate: coordinate,
        round_trip_in_km: round(Float.round(distance / 1000) * 2),
        round_trip_in_hours: Float.round(duration / 3600, 2) * 2
      }
    end)
    |> Enum.map(fn {:ok, a} -> a end)
    |> Enum.sort(&(&1.name < &2.name))
  end
end
