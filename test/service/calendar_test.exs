defmodule Service.CalendarTest do
  use ExUnit.Case, async: true

  @now ~U[2026-10-20 12:00:00Z]

  test "an event in UTC, with its text escaped and lines ending in CRLF" do
    ics =
      Service.Calendar.event(
        %{
          uid: "activity-7@sarduty.com",
          title: "Rope rescue, high lines; night",
          starts_at: ~U[2026-10-23 02:00:00Z],
          ends_at: ~U[2026-10-23 05:00:00Z],
          location: "Hall\nNorth Vancouver",
          url: "https://example.com/a/7"
        },
        @now
      )

    lines = String.split(ics, "\r\n", trim: true)
    assert "DTSTART:20261023T020000Z" in lines
    assert "DTEND:20261023T050000Z" in lines
    assert "DTSTAMP:20261020T120000Z" in lines
    assert "SUMMARY:Rope rescue\\, high lines\; night" in lines
    assert "LOCATION:Hall\\nNorth Vancouver" in lines
    assert "URL:https://example.com/a/7" in lines
    assert String.ends_with?(ics, "END:VCALENDAR\r\n")
  end

  test "no end is an hour, and no place or link leaves the lines out" do
    lines =
      %{
        uid: "u",
        title: "AGM",
        starts_at: ~U[2026-11-04 03:30:00Z],
        ends_at: nil,
        location: nil,
        url: nil
      }
      |> Service.Calendar.event(@now)
      |> String.split("\r\n", trim: true)

    assert "DTEND:20261104T043000Z" in lines
    refute Enum.any?(lines, &String.starts_with?(&1, ["LOCATION", "URL"]))
  end
end
