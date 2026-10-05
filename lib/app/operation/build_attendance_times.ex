defmodule App.Operation.BuildAttendanceTimes do
  alias App.Model.Activity
  alias App.Model.AttendanceScan

  # Turns the door's scans into each member's arrival and departure. Pure: the caller
  # loads the scans.
  #
  # - The latest scan of each kind wins, so scanning again fixes a mistake.
  # - Arriving up to 30 minutes before the start counts as the start, and leaving up to
  #   30 minutes after the end counts as the end. Earlier arrivals and later departures
  #   keep their own time: they came to set up or stayed to pack.
  # - A missing arrival uses the start, and a missing departure the end, with a note.
  # - Leaving at or before arriving can't be sent: the times need fixing first.
  @grace_minutes 30

  def grace_minutes, do: @grace_minutes

  @doc """
  One map per member with a scan, ordered by name:
  `%{member: member, arrived_at: dt, left_at: dt, notes: [note]}`. A note is
  `:no_arrival`, `:no_departure`, or `:left_before_arriving`.
  """
  def call(%Activity{} = activity, scans) do
    scans
    |> Enum.group_by(& &1.member_id)
    |> Enum.map(fn {_member_id, member_scans} -> build(activity, member_scans) end)
    |> Enum.sort_by(&String.downcase(&1.member.name))
  end

  defp build(activity, scans) do
    arrival = latest(scans, "arrived")
    departure = latest(scans, "left")

    {arrived_at, arrival_notes} =
      if arrival,
        do: {snap_arrival(activity, AttendanceScan.time(arrival)), []},
        else: {activity.started_at, [:no_arrival]}

    {left_at, departure_notes} =
      if departure,
        do: {snap_departure(activity, AttendanceScan.time(departure)), []},
        else: {activity.finished_at, [:no_departure]}

    order_notes =
      if DateTime.compare(left_at, arrived_at) == :gt, do: [], else: [:left_before_arriving]

    %{
      member: hd(scans).member,
      arrived_at: truncate(arrived_at),
      left_at: truncate(left_at),
      notes: arrival_notes ++ departure_notes ++ order_notes
    }
  end

  defp latest(scans, kind) do
    scans
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.max_by(&{DateTime.to_unix(&1.scanned_at, :microsecond), &1.id}, fn -> nil end)
  end

  defp snap_arrival(%Activity{started_at: started_at}, time) do
    grace_start = DateTime.add(started_at, -@grace_minutes, :minute)
    if within?(time, grace_start, started_at), do: started_at, else: time
  end

  defp snap_departure(%Activity{finished_at: finished_at}, time) do
    grace_end = DateTime.add(finished_at, @grace_minutes, :minute)
    if within?(time, finished_at, grace_end), do: finished_at, else: time
  end

  defp within?(time, from, to),
    do: DateTime.compare(time, from) != :lt and DateTime.compare(time, to) != :gt

  # D4H keeps whole minutes, so seconds would show as a change that isn't one.
  defp truncate(datetime),
    do: datetime |> DateTime.truncate(:second) |> Map.put(:second, 0)

  @doc "Whether the times can go to D4H."
  def sendable?(%{notes: notes}), do: :left_before_arriving not in notes
end
