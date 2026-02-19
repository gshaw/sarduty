defmodule Service.Format do
  @moduledoc """
    Useful functions for formatting data into strings.
  """

  def count(n, one: one, many: many) do
    template = if n == 1, do: one, else: many
    String.replace(template, "%d", Integer.to_string(n))
  end

  def date_long(datetime, timezone), do: datetime(datetime, timezone, "%B %-d, %Y")
  def date_short(datetime, timezone), do: datetime(datetime, timezone, "%x")
  def datetime_short(datetime, timezone), do: datetime(datetime, timezone, "%c")
  def datetime_medium(datetime, timezone), do: datetime(datetime, timezone, "%a %c")

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

  def months_or_years_ago(date) do
    months_or_years_distance(date, DateTime.utc_now())
  end

  def months_or_years_distance(started_at, finished_at) do
    months = Service.Convert.duration_to_months(started_at, finished_at)
    years = round(months / 12)

    cond do
      months < 1 -> "less than a month"
      months == 1 -> "1 month"
      months <= 18 -> "#{months} months"
      # years == 1 -> "1 year" (not needed since 18 months is the cutoff)
      true -> "#{years} years"
    end
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

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def duration_as_hours_minutes_long(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    hours_str =
      cond do
        hours == 0 -> nil
        hours == 1 -> "1 hour"
        true -> "#{hours} hours"
      end

    mins_str =
      cond do
        mins == 0 -> nil
        mins == 1 -> "1 minute"
        true -> "#{mins} minutes"
      end

    case {hours_str, mins_str} do
      {nil, nil} -> "0 hours"
      {nil, m} -> m
      {h, nil} -> h
      {h, m} -> "#{h}, #{m}"
    end
  end

  def duration_as_hours_minutes_long(minutes) when is_float(minutes) do
    duration_as_hours_minutes_long(round(minutes))
  end

  def duration_as_hours_minutes_medium(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours == 1 and mins == 0 -> "1 hour"
      mins == 0 -> "#{hours} hours"
      hours == 0 -> "#{mins} min"
      true -> "#{hours}h #{mins}m"
    end
  end

  def duration_as_hours_minutes_medium(minutes) when is_float(minutes) do
    duration_as_hours_minutes_medium(round(minutes))
  end

  def duration_as_hours_minutes_short(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "#{hours}:#{String.pad_leading("#{mins}", 2, "0")}"
  end

  def duration_as_hours_minutes_short(minutes) when is_float(minutes) do
    duration_as_hours_minutes_short(round(minutes))
  end
end
