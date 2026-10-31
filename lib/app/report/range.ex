defmodule App.Report.Range do
  @moduledoc """
  Date ranges in a team's time zone, as the UTC `{start, finish}` a query compares with:
  start inclusive, finish exclusive. Pure.

  LAST_N_DAYS:n reaches back n days and takes in today; NEXT_N_DAYS:n takes in today and
  the n days after it; LAST_N_MONTHS:n reaches back n months and takes in today.
  """

  alias App.Report.Context

  @doc "The range a date range's name and number say, on the context's day."
  def of("NOW", _n, %Context{now: now}), do: {now, now}

  def of(name, n, %Context{today: today, timezone: timezone}) do
    {first, last} = days(name, n, today)
    {midnight(first, timezone), midnight(Date.add(last, 1), timezone)}
  end

  @doc "One day in `context`'s time zone."
  def day(%Date{} = date, %Context{timezone: timezone}),
    do: {midnight(date, timezone), midnight(Date.add(date, 1), timezone)}

  defp days("TODAY", _n, today), do: {today, today}

  defp days("THIS_MONTH", _n, today),
    do: {Date.beginning_of_month(today), Date.end_of_month(today)}

  defp days("LAST_MONTH", _n, today), do: month_before(today)
  defp days("THIS_YEAR", _n, today), do: year(today.year)
  defp days("LAST_YEAR", _n, today), do: year(today.year - 1)
  defp days("LAST_N_DAYS", n, today), do: {Date.add(today, -n), today}
  defp days("NEXT_N_DAYS", n, today), do: {today, Date.add(today, n)}
  defp days("LAST_N_MONTHS", n, today), do: {Date.shift(today, month: -n), today}

  defp year(year), do: {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}

  defp month_before(today) do
    first = today |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()
    {first, Date.end_of_month(first)}
  end

  defp midnight(date, timezone) do
    date
    |> DateTime.new(~T[00:00:00], timezone)
    |> first_time()
    |> DateTime.shift_zone!("Etc/UTC")
  end

  # A midnight that clocks skip starts when they do; one they pass twice, the first time.
  defp first_time({:ok, datetime}), do: datetime
  defp first_time({:gap, _before, after_gap}), do: after_gap
  defp first_time({:ambiguous, first, _second}), do: first
end
