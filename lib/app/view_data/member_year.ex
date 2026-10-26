defmodule App.ViewData.MemberYear do
  @moduledoc """
  A member's year in numbers (#576), for Your membership and the year page: hours as the
  tax credit letter counts them, activities and incidents, each against the year before,
  a value a month for the sparklines, and hours a month by kind. Pure: the member's
  attended rows with their activity in, numbers out.
  """

  alias App.Operation.CountTaxCreditHours
  alias App.ViewData.MemberRecords
  alias App.ViewData.TeamDashboardCharts
  alias Service.Format
  alias Service.YearRange

  @doc """
  Primary, secondary, and total minutes for the rows that started in `year`, as the
  letter counts them (`CountTaxCreditHours.count/4`). A row's activity is a chore
  activity when its `chore_minutes` is set (`MemberRecords.attendances/3`).
  """
  def hours([], _year, _timezone, _hours_tags), do: CountTaxCreditHours.zero()

  def hours([first | _rest] = rows, year, timezone, hours_tags) do
    rows
    |> Enum.map(
      &%{
        member_id: &1.member_id,
        started_at: &1.started_at,
        finished_at: &1.finished_at,
        duration_in_minutes: &1.duration_in_minutes,
        tags: &1.activity.tags,
        chore: is_integer(&1.activity.chore_minutes)
      }
    )
    |> CountTaxCreditHours.count(year, timezone, hours_tags)
    |> CountTaxCreditHours.get(first.member_id)
  end

  @doc "The activities the rows are for, each counted once."
  def activities(rows), do: rows |> Enum.uniq_by(& &1.activity_id) |> length()

  @doc "The incidents the rows are for, each counted once."
  def incidents(rows),
    do:
      rows
      |> Enum.uniq_by(& &1.activity_id)
      |> Enum.count(&(&1.activity.activity_kind == "incident"))

  @doc """
  The year page's numbers. `rows` started in `year` and `before` in the year before.
  This year compares with the same days of last year; a past year with the whole year
  before it. Each comparison is `{this, before}`, with hours in whole hours.
  """
  def summary(rows, before, year, now, timezone, hours_tags) do
    this_year? = year == YearRange.year_in(now, timezone)
    before = compared_with(before, this_year?, now)
    by_month = Enum.group_by(rows, &month(&1.started_at, timezone))
    total = fn rows, year -> hours(rows, year, timezone, hours_tags).total_minutes end

    %{
      total_minutes: total.(rows, year),
      activities: activities(rows),
      incidents: incidents(rows),
      versus: versus(rows, before, total.(rows, year), total.(before, year - 1)),
      monthly: monthly(by_month, months(year, this_year?, now, timezone), &total.(&1, year)),
      hour_columns: Enum.map(1..12, &hour_column(Date.new!(year, &1, 1), by_month))
    }
  end

  defp versus(rows, before, minutes, minutes_before) do
    %{
      hours: {div(minutes, 60), div(minutes_before, 60)},
      activities: {activities(rows), activities(before)},
      incidents: {incidents(rows), incidents(before)}
    }
  end

  # A value a month for each sparkline. `total` gives a month's letter minutes.
  defp monthly(by_month, months, total) do
    rows = Enum.map(months, &Map.get(by_month, &1, []))

    %{
      hours: Enum.map(rows, &div(total.(&1), 60)),
      activities: Enum.map(rows, &activities/1),
      incidents: Enum.map(rows, &incidents/1)
    }
  end

  # This year against last year up to this time last year.
  defp compared_with(before, false, _now), do: before

  defp compared_with(before, true, now),
    do: Enum.filter(before, &DateTime.before?(&1.started_at, DateTime.shift(now, year: -1)))

  defp month(datetime, timezone),
    do:
      datetime
      |> DateTime.shift_zone!(timezone)
      |> DateTime.to_date()
      |> Date.beginning_of_month()

  # January to this month for this year, every month for a past one.
  defp months(year, this_year?, now, timezone) do
    last = if this_year?, do: month(now, timezone).month, else: 12
    Enum.map(1..last, &Date.new!(year, &1, 1))
  end

  # Every attended hour in the month, by the activity's kind. Columns are in hours,
  # rounded, so an hour-long training still shows.
  defp hour_column(month, by_month) do
    kind_minutes =
      by_month
      |> Map.get(month, [])
      |> Enum.group_by(&TeamDashboardCharts.kind(&1.activity.activity_kind))
      |> Map.new(fn {kind, rows} -> {kind, minutes(rows)} end)

    %{
      label: Format.month_short(month),
      values: Map.new(kind_minutes, fn {kind, n} -> {kind, round(n / 60)} end),
      tip: tip(month, kind_minutes)
    }
  end

  # "March 2026", then a line for each kind with time.
  defp tip(month, kind_minutes) do
    lines =
      for {key, label} <- TeamDashboardCharts.series(),
          n = Map.get(kind_minutes, key, 0),
          n > 0,
          do: "#{label}: #{Format.duration(n)}"

    Enum.join([Format.month_year_long(month) | lines], "\n")
  end

  defp minutes(rows), do: rows |> Enum.map(&MemberRecords.minutes/1) |> Enum.sum()
end
