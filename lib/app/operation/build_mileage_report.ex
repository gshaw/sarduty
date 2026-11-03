defmodule App.Operation.BuildMileageReport do
  @moduledoc """
  The mileage report for one activity (#230): each attended row's round trip by car from
  the member's home to the activity and to the yard, in whole km. It reads SAR Duty's
  copy, never D4H.

  Mapbox lookups are saved and asked once. call/3 looks up only a home whose address
  changed or was never looked up, and a route between two points never asked before.
  A place or route Mapbox found none for is saved as none; one it didn't answer for is
  asked again next time. build/5 is the arithmetic, and the pure parts are public.
  """

  import Ecto.Query

  alias App.Adapter.Mapbox
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Coordinate
  alias App.Model.HomeCoordinate
  alias App.Model.Member
  alias App.Model.RouteDistance
  alias App.Model.Team
  alias App.Repo

  def call(%Team{} = team, %Activity{} = activity, %DateTime{} = now) do
    rows = attended_rows(activity, now)
    activity_at = point(Coordinate.build(activity.coordinate))
    yard_at = point(Coordinate.build(team.lat, team.lng))
    mapbox = Mapbox.build_context()

    members = rows |> Enum.map(& &1.member) |> Enum.uniq_by(& &1.id)
    homes = look_up_homes(mapbox, team, members, activity_at)
    pairs = pairs(Map.values(homes), activity_at, yard_at)
    distances = look_up_distances(mapbox, team, pairs)

    build(rows, homes, distances, activity_at, yard_at)
  end

  defp attended_rows(activity, now) do
    Attendance
    |> Attendance.attended(now)
    |> where([r], r.activity_id == ^activity.id)
    |> join(:inner, [r], m in assoc(r, :member), as: :member)
    |> order_by([r, member: m], asc: m.name, asc: r.started_at)
    |> preload([member: m], member: m)
    |> Repo.all()
  end

  # ---- Homes ---------------------------------------------------------------------

  # Each member's home as "lat,lng", or why there is none: :no_address, :not_found, or
  # :unknown when Mapbox didn't answer. Saves each place Mapbox found, or found none for.
  defp look_up_homes(mapbox, team, members, near) do
    saved = HomeCoordinate.by_member(team, Enum.map(members, & &1.id))
    asks = homes_to_look_up(members, saved)

    found =
      asks
      |> Task.async_stream(
        fn member -> {member, geocode(mapbox, member.address, near)} end,
        ordered: false,
        timeout: 30_000
      )
      |> Map.new(fn {:ok, {member, result}} -> {member.id, save_home(team, member, result)} end)

    Map.new(members, fn member -> {member.id, found[member.id] || home(member, saved)} end)
  end

  @doc """
  The members whose home to look up: one with an address that was never looked up, or
  was looked up from a different address. Saved homes by member id.
  """
  def homes_to_look_up(members, saved) do
    Enum.filter(members, fn member ->
      address?(member) and
        case saved[member.id] do
          %HomeCoordinate{address: address} -> address != member.address
          nil -> true
        end
    end)
  end

  defp home(member, saved) do
    case saved[member.id] do
      _no_address when not is_binary(member.address) -> :no_address
      %HomeCoordinate{coordinate: nil} -> :not_found
      %HomeCoordinate{coordinate: coordinate} -> coordinate
      nil -> :no_address
    end
  end

  defp address?(%Member{address: address}), do: is_binary(address) and String.trim(address) != ""

  defp geocode(mapbox, address, near) do
    near = near && Coordinate.build(near)

    case Mapbox.fetch_coordinate(mapbox, address, near) do
      {:ok, {lat, lng}} -> {:ok, point(Coordinate.build(lat, lng))}
      {:error, :not_found} -> :not_found
      {:error, _reason} -> :unknown
    end
  end

  defp save_home(team, member, {:ok, coordinate}) do
    HomeCoordinate.save!(team, member, member.address, coordinate)
    coordinate
  end

  defp save_home(team, member, :not_found) do
    HomeCoordinate.save!(team, member, member.address, nil)
    :not_found
  end

  defp save_home(_team, _member, :unknown), do: :unknown

  # ---- Routes --------------------------------------------------------------------

  @doc """
  The one-way routes the report needs, as `{origin, destination}` points: from the
  activity and from the yard to each home found, and from the yard to the activity.
  """
  def pairs(homes, activity_at, yard_at) do
    to_homes =
      for home <- homes, is_binary(home), from <- [activity_at, yard_at], from, do: {from, home}

    yard_to_activity = if activity_at && yard_at, do: [{yard_at, activity_at}], else: []
    Enum.uniq(to_homes ++ yard_to_activity)
  end

  # Metres by pair, nil for no route, and missing for one Mapbox didn't answer.
  defp look_up_distances(mapbox, team, pairs) do
    saved = RouteDistance.by_pair(team, pairs)

    found =
      pairs
      |> Enum.reject(&Map.has_key?(saved, &1))
      |> Task.async_stream(fn pair -> {pair, drive(mapbox, pair)} end,
        ordered: false,
        timeout: 30_000
      )
      |> Enum.flat_map(fn
        {:ok, {_pair, :unknown}} -> []
        {:ok, {pair, metres}} -> [{pair, metres}]
      end)
      |> Map.new()

    RouteDistance.save_all!(team, found)
    Map.merge(saved, found)
  end

  defp drive(mapbox, {from, to}) do
    case Mapbox.fetch_driving_info(mapbox, Coordinate.build(from), Coordinate.build(to)) do
      {:ok, metres, _seconds} -> round(metres)
      {:error, :no_route} -> nil
      {:error, _reason} -> :unknown
    end
  end

  # ---- The report ------------------------------------------------------------------

  @doc """
  The report from the attended rows (member preloaded), each member's home by member id
  (a point, or why there is none), one-way metres by `{origin, destination}`, and the
  activity's and yard's points. A row's km is nil when there is no route; `home` says
  why when there is no home. `two_rows?` marks a member with more than one row, so a
  page can tell them apart by day.
  """
  def build(rows, homes, distances, activity_at, yard_at) do
    counts = Enum.frequencies_by(rows, & &1.member_id)

    %{
      rows:
        Enum.map(rows, fn row ->
          home = homes[row.member_id]

          %{
            attendance: row,
            member: row.member,
            home: home,
            two_rows?: counts[row.member_id] > 1,
            activity_km: round_trip_km(distances, activity_at, home),
            yard_km: round_trip_km(distances, yard_at, home)
          }
        end),
      yard_to_activity_km: round_trip_km(distances, yard_at, activity_at)
    }
  end

  defp round_trip_km(distances, from, to) when is_binary(from) and is_binary(to) do
    case distances[{from, to}] do
      metres when is_integer(metres) -> round(metres / 1000 * 2)
      nil -> nil
    end
  end

  defp round_trip_km(_distances, _from, _to), do: nil

  defp point(nil), do: nil
  defp point(coordinate), do: Coordinate.to_string(coordinate, 5)
end
