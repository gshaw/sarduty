defmodule Service.Format do
  @moduledoc """
    Useful functions for formatting data into strings.
  """

  def long_date(datetime, timezone), do: datetime(datetime, timezone, "%B %-d, %Y")
  def short_date(datetime, timezone), do: datetime(datetime, timezone, "%x")
  def short_datetime(datetime, timezone), do: datetime(datetime, timezone, "%c")
  def medium_datetime(datetime, timezone), do: datetime(datetime, timezone, "%a %c")

  defp datetime(nil, _timezone, _format), do: nil

  defp datetime(datetime, timezone, format) do
    user_options = [
      preferred_datetime: "%b %-d, %Y %H:%M",
      preferred_date: "%b %-d, %Y"
    ]

    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime(format, user_options)
  end

  def duration_in_hours(started_at, finished_at) do
    "#{Service.Convert.duration_to_hours(started_at, finished_at)} hours"
  end

  def duration_in_years(started_at, finished_at) do
    "#{Service.Convert.duration_to_years(started_at, finished_at)} years"
  end

  def same_day_datetime(nil, _activity_started_at, _timezone), do: nil

  def same_day_datetime(datetime, activity_started_at, timezone) do
    shifted = DateTime.shift_zone!(datetime, timezone)
    activity_date = activity_started_at |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
    attendance_date = DateTime.to_date(shifted)

    if Date.compare(attendance_date, activity_date) == :eq do
      Calendar.strftime(shifted, "%H:%M")
    else
      Calendar.strftime(shifted, "%b %-d %H:%M")
    end
  end

  def duration_as_hours_minutes_verbose(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours > 0 and mins == 0 -> "#{hours} hour#{if(hours > 1, do: "s", else: "")}"
      hours > 0 and mins > 0 -> "#{hours}h #{mins}m"
      mins > 0 -> "#{mins} min"
      true -> "0 min"
    end
  end

  def duration_as_hours_minutes_verbose(minutes) when is_float(minutes) do
    duration_as_hours_minutes_verbose(round(minutes))
  end

  def duration_as_hours_minutes_concise(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "#{hours}:#{String.pad_leading("#{mins}", 2, "0")}"
  end

  def duration_as_hours_minutes_concise(minutes) when is_float(minutes) do
    duration_as_hours_minutes_concise(round(minutes))
  end
end
