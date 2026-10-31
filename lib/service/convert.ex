defmodule Service.Convert do
  @moduledoc """
    Useful functions for converting data.
  """

  @doc """
  Minutes from hours a person typed, such as "1.5" or "2". Blank or not a number is 0,
  and a negative number is 0.
  """
  def hours_to_minutes(hours) when is_binary(hours) do
    case hours |> String.trim() |> Float.parse() do
      {hours, ""} -> hours_to_minutes(hours)
      _not_a_number -> 0
    end
  end

  def hours_to_minutes(hours) when is_number(hours), do: max(round(hours * 60), 0)
  def hours_to_minutes(nil), do: 0

  @doc """
  Minutes from a duration someone typed: "45m", "2h", "2.5h", "1h 30m", or "1:30". A bare
  whole number is hours up to 24, since most things here take an hour or more, and
  minutes from 25, which few of them last in hours; "25h" is 25 hours. Nil when it is
  none of these. A duration box shows minutes with duration_text/1.
  """
  def parse_duration(text) when is_binary(text) do
    squeezed = text |> String.downcase() |> String.replace(~r/\s+/, "")

    Enum.find_value(duration_formats(), fn {regex, kind} ->
      if parts = Regex.run(regex, squeezed, capture: :all_but_first),
        do: duration_minutes(kind, parts)
    end)
  end

  def parse_duration(_text), do: nil

  # h, hr, hrs, hour, hours; m, min, mins, minute, minutes.
  defp duration_formats do
    [
      {~r/^(\d+)$/, :bare},
      {~r/^(\d+(?:\.\d+)?|\.\d+)(?:h|hrs?|hours?)?$/, :hours},
      {~r/^(\d+)(?:m|mins?|minutes?)$/, :minutes},
      {~r/^(\d+)(?:h|hrs?|hours?)(\d+)(?:m|mins?|minutes?)?$/, :hours_minutes},
      {~r/^(\d+):([0-5]\d)$/, :hours_minutes}
    ]
  end

  defp duration_minutes(:bare, [number]) do
    number = String.to_integer(number)
    if number > 24, do: number, else: number * 60
  end

  defp duration_minutes(:hours, [hours]), do: round(decimal(hours) * 60)
  defp duration_minutes(:minutes, [minutes]), do: String.to_integer(minutes)

  defp duration_minutes(:hours_minutes, [hours, minutes]),
    do: String.to_integer(hours) * 60 + String.to_integer(minutes)

  defp decimal("." <> _rest = number), do: decimal("0" <> number)
  defp decimal(number), do: number |> Float.parse() |> elem(0)

  @doc ~s(Minutes as a duration box shows them, for parse_duration/1 to read back: "1h 30m".)
  def duration_text(nil), do: nil
  def duration_text(minutes) when minutes < 60, do: "#{minutes}m"
  def duration_text(minutes) when rem(minutes, 60) == 0, do: "#{div(minutes, 60)}h"
  def duration_text(minutes), do: "#{div(minutes, 60)}h #{rem(minutes, 60)}m"

  @doc ~s(Minutes as hours for a form field: 90 is "1.5", 120 is "2".)
  def minutes_to_hours(nil), do: "0"

  def minutes_to_hours(minutes) when is_integer(minutes) do
    if rem(minutes, 60) == 0,
      do: minutes |> div(60) |> Integer.to_string(),
      else: (minutes / 60) |> Float.round(2) |> Float.to_string()
  end

  def duration_to_minutes(started_at, finished_at) do
    DateTime.diff(finished_at, started_at, :minute)
  end

  def duration_to_hours(started_at, finished_at) do
    minutes = duration_to_minutes(started_at, finished_at)
    Float.round(minutes / 60.0, 1)
  end

  @doc """
  Whole days from `now` to `datetime`, rounded up, so something ending tomorrow afternoon
  has 1 day left and something ending exactly 60 days from now has 60. Negative once past.
  Format the result with `Service.Format.days/1`.
  """
  def days_until(%DateTime{} = datetime, %DateTime{} = now),
    do: ceil(DateTime.diff(datetime, now) / 86_400)

  @doc """
  How many calendar days after `started_at`'s day `finished_at` falls, in `timezone`: 1
  for 23:00 to 02:00, like the "+1" on a ticket. 0 with no end.
  """
  def days_later(_started_at, nil, _timezone), do: 0

  def days_later(started_at, finished_at, timezone),
    do: finished_at |> local_date(timezone) |> Date.diff(local_date(started_at, timezone))

  defp local_date(datetime, timezone),
    do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

  def duration_to_months(started_at, finished_at) do
    days =
      finished_at
      |> DateTime.to_date()
      |> Date.diff(DateTime.to_date(started_at))

    round(days / 30.44)
  end

  @doc """
  A date and time on the wall clock in `timezone`, in UTC. A time a clock change skips
  is the time after the gap; one it repeats is the first.
  """
  def local_to_utc(%Date{} = date, %Time{} = time, timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, datetime} -> DateTime.shift_zone!(datetime, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
    end
  end

  @doc "A UTC time as `{date, time}` on the wall clock in `timezone`."
  def utc_to_local(%DateTime{} = datetime, timezone) do
    local = DateTime.shift_zone!(datetime, timezone)
    {DateTime.to_date(local), local |> DateTime.to_time() |> Time.truncate(:second)}
  end
end
