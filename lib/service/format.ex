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

  def long_duration(started_at, finished_at) do
    "#{Service.Convert.duration_to_hours(started_at, finished_at)} hours"
  end
end
