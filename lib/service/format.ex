defmodule Service.Format do
  @moduledoc """
    Useful functions for formatting data into strings.
  """

  def legal_date(datetime, timezone), do: datetime(datetime, timezone, "%B %-d, %Y")
  def short_date(datetime, timezone), do: datetime(datetime, timezone, "%x")
  def short_datetime(datetime, timezone), do: datetime(datetime, timezone, "%c")

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
end
