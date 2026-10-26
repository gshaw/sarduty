defmodule App.Operation.CountTaxCreditHours do
  @moduledoc """
  Primary and secondary hours for tax credit letters, counted from each member's own
  attendance rows (#191, #584). The letter and the letter list both count with `count/4`,
  so they always agree. Which tags count comes from `Activity.hours_tags/1`. The public
  explanation of these rules is #592.
  """

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChoreEvent
  alias App.Model.Team
  alias App.Repo

  @zero %{primary_minutes: 0, secondary_minutes: 0, total_minutes: 0}

  def zero, do: @zero

  @doc "Hours by member id for the team's attended rows that started in `year`, by `now`."
  def call(%Team{} = team, year, member_ids \\ nil, now \\ DateTime.utc_now()) do
    team
    |> load_rows(year, member_ids, now)
    |> count(year, team.timezone, Activity.hours_tags(team))
  end

  @doc """
  Hours by member id. Each row is a map with `member_id`, `started_at`, `finished_at`,
  `duration_in_minutes`, its activity's `tags`, and `chore`, true when its activity is
  one of the team's chore activities (`ChoreEvent.totals/1`). `hours_tags` is the team's
  `Activity.hours_tags/1`.

  - Rows count only when they started in `year` in `timezone`, and their activity has
    the primary or secondary hours tag. Primary wins when it has both.
  - A row counts from its own start and finish, not the activity's. D4H's duration is
    the fallback when a time is missing.
  - Overlapping rows for one member count once. Where primary and secondary overlap,
    the overlap is primary.
  - Chore rows are added up and never merged (#584). A chore has a date but no time of
    day, so every chore row starts at 00:00 on the 1st (`BuildChoreEvent`), where it
    would overlap the member's other chores and anything else that day.
  """
  def count(rows, year, timezone, hours_tags) do
    {start, finish} = Service.YearRange.bounds(year, timezone)

    rows
    |> Enum.filter(&started_in?(&1, start, finish))
    |> Enum.map(&Map.put(&1, :kind, Activity.counts_as(&1.tags, hours_tags)))
    |> Enum.reject(&is_nil(&1.kind))
    |> Enum.group_by(& &1.member_id)
    |> Map.new(fn {member_id, member_rows} -> {member_id, count_member(member_rows)} end)
  end

  def get(hours, member_id), do: Map.get(hours, member_id, @zero)

  defp started_in?(%{started_at: nil}, _start, _finish), do: false

  defp started_in?(%{started_at: started_at}, start, finish),
    do: not DateTime.before?(started_at, start) and DateTime.before?(started_at, finish)

  defp count_member(rows) do
    {timed, untimed} = Enum.split_with(rows, &timed?/1)
    {chores, timed} = Enum.split_with(timed, & &1.chore)

    primary = timed |> intervals(:primary) |> merge()
    secondary = timed |> intervals(:secondary) |> merge() |> subtract(primary)

    primary_minutes = minutes(primary, chores, untimed, :primary)
    secondary_minutes = minutes(secondary, chores, untimed, :secondary)

    %{
      primary_minutes: primary_minutes,
      secondary_minutes: secondary_minutes,
      total_minutes: primary_minutes + secondary_minutes
    }
  end

  # A kind's merged time, with its chores and its rows without times added on.
  defp minutes(merged, chores, untimed, kind),
    do:
      seconds_to_minutes(length_of(merged) + length_of(intervals(chores, kind))) +
        duration_sum(untimed, kind)

  defp timed?(row), do: not is_nil(row.started_at) and not is_nil(row.finished_at)

  # A row that finishes before it starts counts nothing.
  defp intervals(rows, kind) do
    for row <- rows, row.kind == kind do
      start = DateTime.to_unix(row.started_at)
      {start, max(start, DateTime.to_unix(row.finished_at))}
    end
  end

  defp merge(intervals) do
    intervals
    |> Enum.sort()
    |> Enum.reduce([], fn
      {start, finish}, [{last_start, last_finish} | rest] when start <= last_finish ->
        [{last_start, max(finish, last_finish)} | rest]

      interval, acc ->
        [interval | acc]
    end)
    |> Enum.reverse()
  end

  # `a` minus `b`, both merged and sorted.
  defp subtract(a, b), do: Enum.flat_map(a, &subtract_all(&1, b))

  defp subtract_all({start, finish}, _b) when start >= finish, do: []
  defp subtract_all(interval, []), do: [interval]

  defp subtract_all({start, finish}, [{b_start, b_finish} | rest]) do
    cond do
      b_finish <= start -> subtract_all({start, finish}, rest)
      b_start >= finish -> [{start, finish}]
      true -> before_part(start, b_start) ++ subtract_all({max(start, b_finish), finish}, rest)
    end
  end

  defp before_part(start, b_start) when b_start > start, do: [{start, b_start}]
  defp before_part(_start, _b_start), do: []

  defp length_of(intervals),
    do: Enum.reduce(intervals, 0, fn {start, finish}, sum -> sum + finish - start end)

  defp seconds_to_minutes(seconds), do: round(seconds / 60)

  defp duration_sum(rows, kind) do
    for row <- rows, row.kind == kind, reduce: 0 do
      sum -> sum + (row.duration_in_minutes || 0)
    end
  end

  @doc """
  The rows `count/4` takes: attended by `now` (Attendance.attended/2) and started in
  `year`, each with `chore` set from the team's chore events.
  """
  def load_rows(%Team{} = team, year, member_ids \\ nil, now \\ DateTime.utc_now()) do
    now
    |> Attendance.attended()
    |> join(:inner, [at], m in assoc(at, :member))
    |> where([at, activity: ac], ac.team_id == ^team.id)
    |> where([at, ..., m], m.team_id == ^team.id)
    |> scope_members(member_ids)
    |> Attendance.started_in(year, team.timezone)
    |> join(:left, [activity: ac], c in subquery(ChoreEvent.totals(team.id)),
      as: :chores,
      on: c.d4h_activity_id == ac.d4h_activity_id
    )
    |> select([at, activity: ac, chores: c], %{
      member_id: at.member_id,
      started_at: at.started_at,
      finished_at: at.finished_at,
      duration_in_minutes: at.duration_in_minutes,
      tags: ac.tags,
      # Typed, or SQLite's 0 for false would be truthy in Elixir.
      chore: type(fragment("? IS NOT NULL", c.d4h_activity_id), :boolean)
    })
    |> Repo.all()
  end

  defp scope_members(query, nil), do: query
  defp scope_members(query, member_ids), do: where(query, [at], at.member_id in ^member_ids)
end
