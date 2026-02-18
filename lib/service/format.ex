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

  def attendance_datetime(nil, _activity_started_at, _timezone), do: nil

  def attendance_datetime(datetime, activity_started_at, timezone) do
    shifted = DateTime.shift_zone!(datetime, timezone)
    activity_date = activity_started_at |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
    attendance_date = DateTime.to_date(shifted)

    if Date.compare(attendance_date, activity_date) == :eq do
      Calendar.strftime(shifted, "%H:%M")
    else
      Calendar.strftime(shifted, "%b %-d %H:%M")
    end
  end
end
