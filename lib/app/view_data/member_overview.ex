defmodule App.ViewData.MemberOverview do
  @moduledoc """
  What a member's overview draws (#389): this year's numbers, hours by kind, the
  activities for the map, and the latest few. Pure: the member's attended rows (with
  their activity, newest first), their qualification groups from
  `MemberRecords.group_awards/2`, and `now` in.
  """

  alias App.ViewData.MemberRecords

  @kinds [{"incident", "Incidents"}, {"exercise", "Exercises"}, {"event", "Events"}]

  def build(attendances, qualification_groups, now, timezone) do
    year = Service.YearRange.year_in(now, timezone)

    this_year =
      Enum.filter(attendances, &(Service.YearRange.year_in(&1.started_at, timezone) == year))

    a_year_ago = DateTime.shift(now, year: -1)

    %{
      year: year,
      minutes: this_year |> Enum.map(&MemberRecords.minutes/1) |> Enum.sum(),
      activities: length(this_year),
      incidents: Enum.count(this_year, &(&1.activity.activity_kind == "incident")),
      hours_by_kind: hours_by_kind(this_year),
      qualifications: qualifications(qualification_groups),
      last_12_months: Enum.filter(attendances, &DateTime.after?(&1.started_at, a_year_ago)),
      lately: Enum.take(attendances, 3)
    }
  end

  @doc """
  Minutes by activity kind, `[%{kind:, label:, minutes:}]` in the order incidents,
  exercises, events, leaving out kinds with none. Every attended activity counts, not
  only those with an hours tag.
  """
  def hours_by_kind(attendances) do
    minutes =
      Enum.reduce(attendances, %{}, fn attendance, acc ->
        Map.update(
          acc,
          attendance.activity.activity_kind,
          MemberRecords.minutes(attendance),
          &(&1 + MemberRecords.minutes(attendance))
        )
      end)

    for {kind, label} <- @kinds,
        (minutes[kind] || 0) > 0,
        do: %{kind: kind, label: label, minutes: minutes[kind]}
  end

  @doc "`hours_by_kind/1` as `Web.Components.Chart.bar_list/1` rows."
  def bars(hours_by_kind),
    do:
      for(
        row <- hours_by_kind,
        do: %{label: row.label, value: row.minutes, text: Service.Format.duration(row.minutes)}
      )

  # How many qualifications the member holds now, and the one that expires next.
  defp qualifications(groups) do
    current = for {group, rows} <- groups, group != :expired, row <- rows, do: row.award

    %{
      count: length(current),
      next:
        current |> Enum.filter(& &1.ends_at) |> Enum.min_by(& &1.ends_at, DateTime, fn -> nil end)
    }
  end
end
