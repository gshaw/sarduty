defmodule Service.DayRange do
  @moduledoc """
  Whole days in a team's time zone, as UTC bounds for queries.

  Bounds are `NaiveDateTime` in UTC, like `Service.YearRange`, so they compare
  correctly against stored times with and without the `Z`.
  """

  @doc """
  The UTC `{start, finish}` of the `days` days before `now`'s day in
  `timezone`, that day, and the `days` days after it: start is inclusive,
  finish exclusive.
  """
  def around(%DateTime{} = now, timezone, days) do
    today = now |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

    {start_of_day(Date.add(today, -days), timezone),
     start_of_day(Date.add(today, days + 1), timezone)}
  end

  defp start_of_day(date, timezone) do
    date
    |> DateTime.new!(~T[00:00:00], timezone)
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
  end
end
