defmodule Service.DayRange do
  @moduledoc """
  Whole days in a team's time zone, as UTC bounds for queries.

  Bounds are UTC `DateTime`s, like `Service.YearRange`.
  """

  @doc """
  The UTC `{start, finish}` of the `days` days before `now`'s day in
  `timezone`, that day, and the `days` days after it: start is inclusive,
  finish exclusive.
  """
  def around(%DateTime{} = now, timezone, days) do
    today = Service.Period.today(now, timezone)

    {start_of_day(Date.add(today, -days), timezone),
     start_of_day(Date.add(today, days + 1), timezone)}
  end

  @doc """
  The UTC `{start, finish}` of the last `days` days (#784): today in `timezone` and the
  `days` days before it, whole days. SAR Duty's one rule for "last 30 days", the same
  as a report's `LAST_N_DAYS:30`.
  """
  def last(%DateTime{} = now, timezone, days) do
    today = Service.Period.today(now, timezone)
    {start_of_day(Date.add(today, -days), timezone), start_of_day(Date.add(today, 1), timezone)}
  end

  @doc """
  When `date` starts in `timezone`, in UTC. A midnight that clocks skip starts when they
  do; one they pass twice, the first time.
  """
  def start_of_day(%Date{} = date, timezone) do
    date
    |> DateTime.new(~T[00:00:00], timezone)
    |> first_time()
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp first_time({:ok, datetime}), do: datetime
  defp first_time({:gap, _before, after_gap}), do: after_gap
  defp first_time({:ambiguous, first, _second}), do: first
end
