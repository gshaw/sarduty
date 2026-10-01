defmodule Service.YearRange do
  @moduledoc """
  Calendar years in a team's time zone, as UTC bounds for queries.

  Bounds are `NaiveDateTime` in UTC, with no `Z`. Stored times are a mix of
  `2024-10-24T02:00:00Z` and `2024-10-24T02:00:00`, and a bound without the `Z`
  compares correctly against both as text. Compare with
  `type(^start, :naive_datetime)`.
  """

  @doc """
  The UTC `{start, finish}` of `year` in `timezone`: start is inclusive,
  finish exclusive.
  """
  def bounds(year, timezone) when is_binary(year), do: bounds(String.to_integer(year), timezone)

  def bounds(year, timezone) when is_integer(year) do
    {start_of_year(year, timezone), start_of_year(year + 1, timezone)}
  end

  @doc """
  The years from `first` to `last` in `timezone`, newest first. Empty when
  either is nil.
  """
  def years(nil, _last, _timezone), do: []
  def years(_first, nil, _timezone), do: []

  def years(%DateTime{} = first, %DateTime{} = last, timezone) do
    Enum.to_list(year_in(last, timezone)..year_in(first, timezone)//-1)
  end

  @doc "The year `datetime` falls in, in `timezone`."
  def year_in(%DateTime{} = datetime, timezone) do
    DateTime.shift_zone!(datetime, timezone).year
  end

  defp start_of_year(year, timezone) do
    year
    |> Date.new!(1, 1)
    |> DateTime.new!(~T[00:00:00], timezone)
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
  end
end
