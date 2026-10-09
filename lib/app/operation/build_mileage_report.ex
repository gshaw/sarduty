defmodule App.Operation.BuildMileageReport do
  @moduledoc """
  The mileage report for one activity: each attending member's round trip by car from
  home to the activity and to the yard. call/3 reads D4H and asks Mapbox for each
  route; build/3 does the arithmetic.
  """

  alias App.Adapter.D4H
  alias App.Adapter.Mapbox

  def call(d4h, activity_id, activity_kind) do
    {:ok, team} = D4H.fetch_team(d4h)
    activity = D4H.fetch_activity(d4h, activity_id, activity_kind)
    team_members = D4H.fetch_team_members(d4h)
    attendance_records = D4H.fetch_activity_attendance(d4h, activity_id, team_members)

    mapbox = Mapbox.build_context()

    routes =
      attendance_records
      |> attending()
      |> Task.async_stream(fn record ->
        {record.member.d4h_member_id,
         member_routes(mapbox, record.member.address, activity.coordinate, team.coordinate)}
      end)
      |> Map.new(fn {:ok, route} -> route end)

    build(attendance_records, routes, drive(mapbox, team.coordinate, activity.coordinate))
  end

  @doc """
  The report from the activity's attendance, each attending member's routes by D4H
  member id, and the yard's route to the activity. A route is `{metres, seconds}` one
  way, or nil when Mapbox found none; a coordinate the member's home, or why it wasn't
  found. Round trips are twice one way, in whole km and hours to a tenth.
  """
  def build(attendance_records, routes, yard_route) do
    attendees =
      attendance_records
      |> attending()
      |> Enum.map(fn record ->
        route = routes[record.member.d4h_member_id]

        %{
          member_id: record.member.d4h_member_id,
          name: record.member.name,
          address: record.member.address,
          coordinate: route.coordinate,
          activity_km: round_trip_km(route.to_activity),
          activity_hours: round_trip_hours(route.to_activity),
          yard_km: round_trip_km(route.to_yard),
          yard_hours: round_trip_hours(route.to_yard)
        }
      end)
      |> Enum.sort_by(& &1.name)

    %{
      attendees: attendees,
      yard_to_activity_km: round_trip_km(yard_route),
      yard_to_activity_hours: round_trip_hours(yard_route)
    }
  end

  defp attending(records), do: Enum.filter(records, &(&1.status == "attending"))

  defp round_trip_km(nil), do: nil
  defp round_trip_km({metres, _seconds}), do: round(metres / 1000 * 2)

  defp round_trip_hours(nil), do: nil
  defp round_trip_hours({_metres, seconds}), do: Float.round(seconds / 3600 * 2, 1)

  defp member_routes(mapbox, address, activity_coordinate, yard_coordinate) do
    case Mapbox.fetch_coordinate(mapbox, address, activity_coordinate) do
      {:ok, coordinate} ->
        %{
          coordinate: coordinate,
          to_activity: drive(mapbox, activity_coordinate, coordinate),
          to_yard: drive(mapbox, yard_coordinate, coordinate)
        }

      {:error, reason, _response} ->
        %{coordinate: reason, to_activity: nil, to_yard: nil}
    end
  end

  defp drive(mapbox, from, to) do
    case Mapbox.fetch_driving_info(mapbox, from, to) do
      {:ok, metres, seconds} -> {metres, seconds}
      {:error, _response} -> nil
    end
  end
end
