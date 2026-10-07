defmodule Service.TimeBuckets do
  @moduledoc """
  Groups times into months, days, and hours of the week in a team's time zone, for charts.

  Every function takes UTC `DateTime`s and the zone, and buckets by the local date, so an
  incident at 23:30 on Dec 31 counts in December, not January.
  """

  @doc "The first day of each of the `count` months ending with `now`'s, oldest first."
  def months(%DateTime{} = now, timezone, count) do
    this_month = now |> local_date(timezone) |> Date.beginning_of_month()
    Enum.map((count - 1)..0//-1, &Date.shift(this_month, month: -&1))
  end

  @doc "The `count` dates ending with `now`'s, oldest first."
  def days(%DateTime{} = now, timezone, count) do
    today = local_date(now, timezone)
    Enum.map((count - 1)..0//-1, &Date.add(today, -&1))
  end

  @doc """
  Counts `{datetime, key}` rows per month and key, for `months`. Returns one
  `{month, %{key => count}}` per month, in order. Rows outside the months are left out.
  """
  def count_by_month(rows, months, timezone) do
    counts =
      Enum.frequencies_by(rows, fn {datetime, key} ->
        {datetime |> local_date(timezone) |> Date.beginning_of_month(), key}
      end)

    Enum.map(months, fn month ->
      {month, for({{^month, key}, n} <- counts, into: %{}, do: {key, n})}
    end)
  end

  @doc "Counts `datetimes` per local date: `%{date => count}`."
  def count_by_day(datetimes, timezone) do
    Enum.frequencies_by(datetimes, &local_date(&1, timezone))
  end

  @doc """
  Counts `datetimes` per day of the week and hour: `%{{day, hour} => count}`. Day 1 is
  Monday, 7 is Sunday. Hour is 0 to 23.
  """
  def count_by_week_hour(datetimes, timezone) do
    Enum.frequencies_by(datetimes, fn datetime ->
      local = DateTime.shift_zone!(datetime, timezone)
      {Date.day_of_week(local), local.hour}
    end)
  end

  @doc """
  `count_by_week_hour/2`'s counts as 7 lists of 24, Monday first. Pages keep lists, not
  maps with tuple keys, since error reporting cannot read tuple keys in LiveView assigns.
  """
  def week_rows(counts) do
    for day <- 1..7, do: for(hour <- 0..23, do: Map.get(counts, {day, hour}, 0))
  end

  @doc """
  The running total of `{datetime, amount}` rows by month of `year`: 12 numbers, January
  first. Months after `now` are nil, so a line stops at today.
  """
  def cumulative_by_month(rows, year, %DateTime{} = now, timezone) do
    totals =
      Enum.reduce(rows, %{}, fn {datetime, amount}, acc ->
        date = local_date(datetime, timezone)
        if date.year == year, do: Map.update(acc, date.month, amount, &(&1 + amount)), else: acc
      end)

    today = local_date(now, timezone)

    1..12
    |> Enum.map_reduce(0, fn month, sum ->
      sum = sum + Map.get(totals, month, 0)
      {if(year < today.year or month <= today.month, do: sum), sum}
    end)
    |> elem(0)
  end

  @doc """
  Which of 5 shades a count gets, 0 for none to 4 for the busiest. Shades split `max` into
  quarters, so 1 always shows as at least shade 1.
  """
  def level(0, _max), do: 0
  def level(_count, max) when max <= 0, do: 0
  def level(count, max), do: min(4, ceil(count * 4 / max))

  defp local_date(datetime, timezone) do
    datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
  end
end
