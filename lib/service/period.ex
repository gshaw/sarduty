defmodule Service.Period do
  @moduledoc """
  The spans of time SAR Duty means by its words for when, defined once so every page and
  job agrees. All take `now` and the team's time zone.

  - **Current**: 7 days either side of today. The activity list's "Current".
  - **Recent**: the last 30 days. The activity list's "Last 30 days" and the drafts count.
  - **Letter season**: January to April. Members file their taxes by April 30.
  - **Open years**: this year, and last year too in letter season. Letters can still be
    made or changed for these years, so their activities must match D4H.
  """

  # A busy team runs about six activities a week, so this fits on one screen.
  @current_days 7
  @recent_days 30
  @letter_months 1..4

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
    DateTime.from_naive!(start, "Etc/UTC")
  end
end
