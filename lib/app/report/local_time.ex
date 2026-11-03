defmodule App.Report.LocalTime do
  @moduledoc """
  A stored UTC time as the team's local time, in SQL. SQLite knows no time zones, so the
  offset comes from the zone's periods in tzdata: nested CASEs that pick each time's offset
  by when it falls, for the years a team's records can span. A fixed offset would put the
  last hour of a summer day in the next one.

  Every value in the SQL comes from tzdata, never from a query, so it is written inline.
  """

  # Records start no earlier than this, and reports look no later.
  @first ~U[1990-01-01 00:00:00Z]
  @last ~U[2045-01-01 00:00:00Z]

  @doc """
  `column`, a UTC time stored as ISO 8601 text, and its offset in `timezone`, as the
  arguments of one of SQLite's date functions: `["date(", args(column, timezone), ")"]` is
  the local day, "2026-10-31". The function reads the time once and moves it.
  """
  def args(column, timezone), do: [column, ", ", offset_sql(column, timezone)]

  @doc "The offset of `column` in `timezone`, as SQLite's datetime modifier: '-25200 seconds'."
  def offset_sql(column, timezone, sign \\ 1) do
    case periods(timezone) do
      [{_until, offset}] ->
        modifier(sign * offset)

      periods ->
        tree(column, periods, sign)
    end
  end

  @doc """
  The start of a day in `timezone` as UTC text, as a stored time is: `day` is SQL for a
  date such as '2026-01-01', and the start is that midnight's own offset. A D4H date
  field holds a day, not a moment, so it reads as the day it says, never the day before.
  The midnight is looked up as if it were UTC, which picks the right period while the
  zone changes its clocks at 01:00 UTC or later, as every Canadian zone does.
  """
  def day_start(day, timezone) do
    as_utc = ["(", day, " || 'T00:00:00Z')"]
    ["strftime('%Y-%m-%dT%H:%M:%SZ', ", day, ", ", offset_sql(as_utc, timezone, -1), ")"]
  end

  # Halves the periods at each CASE, so a time takes 7 comparisons, not one per period
  # since 1990 (#784).
  defp tree(_column, [{_until, offset}], sign), do: modifier(sign * offset)

  defp tree(column, periods, sign) do
    {earlier, later} = Enum.split(periods, div(length(periods), 2))
    {until, _offset} = List.last(earlier)

    [
      "(CASE WHEN ",
      column,
      " < '",
      until,
      "' THEN ",
      tree(column, earlier, sign),
      " ELSE ",
      tree(column, later, sign),
      " END)"
    ]
  end

  defp modifier(seconds), do: "'#{seconds} seconds'"

  # `{until, offset}` for each period from @first to @last, until as stored text. Periods
  # with the same offset in a row are one.
  defp periods(timezone) do
    {:ok, periods} = Tzdata.periods(timezone)
    first = gregorian(@first)
    last = gregorian(@last)

    periods
    |> Enum.filter(fn p -> after?(p.until.utc, first) and before?(p.from.utc, last) end)
    |> Enum.map(fn p -> {p.until.utc, p.utc_off + p.std_off} end)
    |> Enum.chunk_by(&elem(&1, 1))
    |> Enum.map(fn chunk ->
      {until, offset} = List.last(chunk)
      {until_text(until), offset}
    end)
  end

  defp after?(:max, _seconds), do: true
  defp after?(:min, _seconds), do: false
  defp after?(utc, seconds), do: utc > seconds

  defp before?(:min, _seconds), do: true
  defp before?(:max, _seconds), do: false
  defp before?(utc, seconds), do: utc < seconds

  defp until_text(:max), do: nil

  defp until_text(seconds) do
    seconds
    |> :calendar.gregorian_seconds_to_datetime()
    |> NaiveDateTime.from_erl!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp gregorian(datetime),
    do:
      datetime
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()
      |> :calendar.datetime_to_gregorian_seconds()
end
