defmodule App.ViewData.Milestones do
  @moduledoc """
  A member's milestones (#389): a plain, dated list, worked out from attendance,
  `joined_at`, and away periods when the page loads, so past ones show on day one and
  nothing is stored. Pure: the member's attended rows (with their activity, any order),
  `joined_at`, their away periods, and `now` in.

  - **Hours**: 100, 250, 500, 1,000, then every 1,000. Every attended activity counts, not
    only those with an hours tag, and the activity that crossed the line dates it.
  - **Years on the team**: 1, 5, 10, then every 5, counted from `joined_at` without the
    days in away periods. A member who left and rejoined has the gap as an away period,
    since teams reopen their D4H record; leave is left out the same way.
  - **Incidents**: the first, 10, 25, 50, 100, then every 100, dated by the incident.

  A typical team's middle member has about 90 hours a year and the top tenth about 400,
  which set the hour lines.
  """

  alias App.ViewData.MemberRecords

  @doc """
  Milestones reached by `now`, newest first, each `%{kind: :hours | :years | :incidents,
  count:, on: %Date{}, activity:}`. `activity` is the one that reached it, nil for years.
  """
  def build(attendances, joined_at, away_periods, now, timezone) do
    attended = Enum.sort_by(attendances, & &1.started_at, DateTime)
    incidents = Enum.filter(attended, &(&1.activity.activity_kind == "incident"))

    (hours(attended, timezone) ++
       counted(incidents, :incidents, timezone) ++
       years(joined_at, away_periods, now, timezone))
    |> Enum.sort_by(&{Date.to_gregorian_days(&1.on), order(&1.kind), &1.count}, :desc)
  end

  @doc "The lines for a kind, in order, up to `max`."
  def lines(:hours, max), do: stepped([100, 250, 500, 1000], 1000, max)
  def lines(:years, max), do: stepped([1, 5, 10], 5, max)
  def lines(:incidents, max), do: stepped([1, 10, 25, 50, 100], 100, max)

  defp stepped(firsts, step, max) do
    last = List.last(firsts)
    more = Stream.iterate(last + step, &(&1 + step))
    firsts |> Stream.concat(more) |> Enum.take_while(&(&1 <= max))
  end

  # Running minutes; each line is reached by the first row that takes the total to it.
  defp hours(attended, timezone) do
    {reached, _total} =
      Enum.flat_map_reduce(attended, 0, fn attendance, total ->
        after_this = total + MemberRecords.minutes(attendance)

        crossed =
          for hours <- lines(:hours, div(after_this, 60)),
              hours * 60 > total,
              do: milestone(:hours, hours, attendance, timezone)

        {crossed, after_this}
      end)

    reached
  end

  defp counted(rows, kind, timezone) do
    lines = kind |> lines(length(rows)) |> MapSet.new()

    for {attendance, n} <- Enum.with_index(rows, 1),
        n in lines,
        do: milestone(kind, n, attendance, timezone)
  end

  defp years(nil, _away_periods, _now, _timezone), do: []

  defp years(joined_at, away_periods, now, timezone) do
    joined = local_date(joined_at, timezone)
    today = local_date(now, timezone)
    gaps = merge_gaps(away_periods, joined)

    for n <- lines(:years, today.year - joined.year),
        on = joined |> Date.shift(year: n) |> push_past(gaps),
        Date.compare(on, today) != :gt,
        do: %{kind: :years, count: n, on: on, activity: nil}
  end

  # The away periods from the day they joined on, sorted, with overlaps merged into one.
  defp merge_gaps(away_periods, joined) do
    away_periods
    |> Enum.filter(&(Date.compare(&1.ends_on, joined) != :lt))
    |> Enum.map(&{Enum.max([&1.starts_on, joined], Date), &1.ends_on})
    |> Enum.sort_by(&elem(&1, 0), Date)
    |> Enum.reduce([], &merge_gap/2)
    |> Enum.reverse()
  end

  defp merge_gap({first, last} = gap, [{prev_first, prev_last} | rest] = merged) do
    if Date.compare(first, Date.add(prev_last, 1)) != :gt,
      do: [{prev_first, Enum.max([last, prev_last], Date)} | rest],
      else: [gap | merged]
  end

  defp merge_gap(gap, []), do: [gap]

  # Each gap that starts by `on` moves it later by the gap's days, which can bring the
  # next gap in.
  defp push_past(on, gaps) do
    Enum.reduce(gaps, on, fn {first, last}, on ->
      if Date.compare(first, on) != :gt,
        do: Date.add(on, Date.diff(last, first) + 1),
        else: on
    end)
  end

  defp milestone(kind, count, attendance, timezone),
    do: %{
      kind: kind,
      count: count,
      on: local_date(attendance.started_at, timezone),
      activity: attendance.activity
    }

  defp local_date(datetime, timezone),
    do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

  # On the same day, the bigger news first: years, then hours, then incidents.
  defp order(:years), do: 3
  defp order(:hours), do: 2
  defp order(:incidents), do: 1
end
