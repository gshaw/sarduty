defmodule App.Report.LocalTime do
  @moduledoc """
  A stored UTC time as the team's local time, in SQL. SQLite knows no time zones, so the
  offset comes from the zone's periods in tzdata: a CASE that picks each time's offset by
  when it falls, for the years a team's records can span. A fixed offset would put the
  last hour of a summer day in the next one.

  Every value in the SQL comes from tzdata, never from a query, so it is written inline.
  """

  # Records start no earlier than this, and reports look no later.
  @first ~U[1990-01-01 00:00:00Z]
  @last ~U[2045-01-01 00:00:00Z]

  @doc """
  SQL for `column`, a UTC time stored as ISO 8601 text, as the local time in `timezone`:
  SQLite's datetime text, "2026-10-31 14:00:00".
  """
  def sql(column, timezone), do: ["datetime(", column, ", ", offset_sql(column, timezone), ")"]

  @doc "The offset of `column` in `timezone`, as SQLite's datetime modifier: '-25200 seconds'."
  def offset_sql(column, timezone) do
    case periods(timezone) do
      [{_until, offset}] ->
        modifier(offset)

      periods ->
        {last, [{_until, final}]} = Enum.split(periods, -1)

        whens =
          Enum.map(last, fn {until, offset} ->
            [" WHEN ", column, " < '", until, "' THEN ", modifier(offset)]
          end)

        ["(CASE", whens, " ELSE ", modifier(final), " END)"]
    end
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
