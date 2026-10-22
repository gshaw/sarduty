defmodule Service.Calendar do
  @moduledoc """
  One event as an iCalendar file (RFC 5545), for Add to calendar on an activity's page
  (#389, #406). Phones and calendar apps open it and offer to add the event.
  """

  @doc """
  The file for `%{uid:, title:, starts_at:, ends_at:, location:, url:}`. Times are UTC;
  `location` and `url` may be nil or blank, and `ends_at` falls back to an hour after the start.
  """
  def event(event, now) do
    ends_at = event.ends_at || DateTime.add(event.starts_at, 3600)

    [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//SAR Duty//Activity//EN",
      "BEGIN:VEVENT",
      "UID:#{event.uid}",
      "DTSTAMP:#{stamp(now)}",
      "DTSTART:#{stamp(event.starts_at)}",
      "DTEND:#{stamp(ends_at)}",
      "SUMMARY:#{escape(event.title)}",
      event.location not in [nil, ""] && "LOCATION:#{escape(event.location)}",
      event.url not in [nil, ""] && "URL:#{event.url}",
      "END:VEVENT",
      "END:VCALENDAR"
    ]
    |> Enum.filter(& &1)
    |> Enum.map_join(&(&1 <> "\r\n"))
  end

  defp stamp(datetime),
    do: datetime |> DateTime.shift_zone!("Etc/UTC") |> Calendar.strftime("%Y%m%dT%H%M%SZ")

  # Text values escape backslashes, semicolons, commas, and line breaks.
  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\;")
    |> String.replace(",", "\\,")
    |> String.replace(~r/\r?\n/, "\\n")
  end
end
