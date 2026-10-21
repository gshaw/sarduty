defmodule Service.Period do
  @moduledoc """
  The spans of time SAR Duty means by its words for when, defined once so every page and
  job agrees. All take `now` and the team's time zone.

  - **Current**: 7 days either side of today. The activity list's "Current".
  - **Recent**: the last 30 days. The activity list's "Last 30 days" and the drafts count.
  - **Letter season**: January to April. Members file their taxes by April 30.
  - **Open years**: this year, and last year too in letter season. Letters can still be
    made or changed for these years, so their activities must match D4H.
  - **A filter's period**: All, a year as `"2026"`, or the last 30 to 365 days as
    `"90d"`, ending now. The members list and a member's activities offer the same.
  """

  # A busy team runs about six activities a week, so this fits on one screen.
  @current_days 7
  @recent_days 30
  @letter_months 1..4
  @rolling_days [30, 60, 90, 180, 365]

  @doc "Today's date in `timezone`."
  def today(%DateTime{} = now, timezone),
    do: now |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

  @doc "Days either side of today that Current shows."
  def current_days, do: @current_days

  @doc "The UTC `{start, finish}` of Current, as `Service.DayRange` bounds."
  def current(%DateTime{} = now, timezone),
    do: Service.DayRange.around(now, timezone, @current_days)

  @doc "Days back that Recent reaches."
  def recent_days, do: @recent_days

  @doc "Whether `now` falls in letter season."
  def letter_season?(%DateTime{} = now, timezone),
    do: DateTime.shift_zone!(now, timezone).month in @letter_months

  @doc "The open years, oldest first."
  def open_years(%DateTime{} = now, timezone) do
    year = Service.YearRange.year_in(now, timezone)
    if letter_season?(now, timezone), do: [year - 1, year], else: [year]
  end

  @doc "When the oldest open year starts, as a UTC `DateTime`."
  def open_years_start(%DateTime{} = now, timezone) do
    {start, _finish} = now |> open_years(timezone) |> hd() |> Service.YearRange.bounds(timezone)
    start
  end

  @doc ~s(The rolling periods a filter offers, as `{label, value}`: "Last 90 days" is `"90d"`.)
  def rolling_kinds, do: Enum.map(@rolling_days, &{"Last #{Service.Format.days(&1)}", "#{&1}d"})

  @doc ~s(Whether `value` is a period a filter takes: `"all"`, a year, or a rolling period.)
  def valid?(value) when is_binary(value),
    do: value == "all" or value =~ ~r/\A\d{4}\z/ or value in Enum.map(@rolling_days, &"#{&1}d")

  def valid?(_value), do: false

  @doc """
  The UTC `{start, finish}` a year or rolling period covers, as `Service.YearRange`
  bounds: start inclusive, finish exclusive. A rolling period ends at `now`.
  """
  def bounds(year, timezone, _now) when is_integer(year),
    do: Service.YearRange.bounds(year, timezone)

  def bounds(period, timezone, %DateTime{} = now) when is_binary(period) do
    case Integer.parse(period) do
      {days, "d"} ->
        finish = DateTime.truncate(now, :second)
        {DateTime.add(finish, -days, :day), finish}

      {_year, ""} ->
        Service.YearRange.bounds(period, timezone)
    end
  end
end
