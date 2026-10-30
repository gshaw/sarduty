defmodule App.ViewData.MemberRecords do
  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChoreEvent
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Operation.BuildGroupRulePreview
  alias App.Repo

  # A member's own records, for their page (#156, stage 2): hours and attended activities
  # for one year, the activities they're signed up for, and their qualifications. Every
  # query filters by the member and their team. Expects the member with its team, as
  # Member.get_logins/2 returns it.

  @doc "The years the member attended something in, and this year, newest first."
  def years(%Member{} = member, now) do
    this_year = Service.YearRange.year_in(now, member.team.timezone)

    member
    |> attended_query(now)
    |> Attendance.years(member.team.timezone)
    |> then(&[this_year | &1])
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  @doc """
  The years for the member's year page (#406): from this year back to the year they
  joined, and any earlier year they attended in, newest first.
  """
  def years_on_team(%Member{} = member, now) do
    this_year = Service.YearRange.year_in(now, member.team.timezone)

    joined =
      if member.joined_at,
        do: Service.YearRange.year_in(member.joined_at, member.team.timezone),
        else: this_year

    (Enum.to_list(this_year..min(joined, this_year)//-1) ++ years(member, now))
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  @doc """
  The member's attended rows that started in `year`, newest first, with the activity. A
  chore activity has its `chore_minutes` (#575), so the year's hours add its rows up as
  the letter does (#584).
  """
  def attendances(%Member{} = member, year, now) do
    member
    |> attended_query(now)
    |> Attendance.started_in(year, member.team.timezone)
    |> order_by([at], desc: at.started_at)
    |> preload([activity: ac], activity: ac)
    |> Repo.all()
    |> put_chore_minutes(member.team_id)
  end

  defp put_chore_minutes(rows, team_id) do
    minutes =
      team_id |> ChoreEvent.totals() |> Repo.all() |> Map.new(&{&1.d4h_activity_id, &1.minutes})

    Enum.map(rows, &put_in(&1.activity.chore_minutes, minutes[&1.activity.d4h_activity_id]))
  end

  @doc "Every row the member attended, newest first, with the activity."
  def attended(%Member{} = member, now) do
    member
    |> attended_query(now)
    |> order_by([at], desc: at.started_at)
    |> preload([activity: ac], activity: ac)
    |> Repo.all()
  end

  @doc """
  The member's rows for activities still to start, soonest first, with the activity. D4H
  marks a sign-up attending before the activity happens (#364).
  """
  def signed_up(%Member{} = member, now) do
    member
    |> member_query(&Attendance.signed_up(&1, now))
    |> order_by([at], asc: at.started_at)
    |> preload([activity: ac], activity: ac)
    |> Repo.all()
  end

  @doc """
  Which hours a row's activity counts for, as its tags say: `:primary`, `:secondary`, or
  `:other` for neither. `hours_tags` is the team's `Activity.hours_tags/1`.
  """
  def hours_kind(%{activity: activity}, hours_tags),
    do: Activity.counts_as(activity.tags, hours_tags) || :other

  @doc "The minutes on rows whose activity has neither hours tag, the year page's Other."
  def other_minutes(attendances, hours_tags) do
    attendances
    |> Enum.filter(&(hours_kind(&1, hours_tags) == :other))
    |> Enum.map(&minutes/1)
    |> Enum.sum()
  end

  @doc "How long the member was there: their own times, else D4H's duration."
  def minutes(%{started_at: %DateTime{} = started_at, finished_at: %DateTime{} = finished_at}),
    do: max(0, div(DateTime.diff(finished_at, started_at), 60))

  def minutes(%{duration_in_minutes: minutes}), do: minutes || 0

  @doc "The member's qualifications, as `qualification_rows/2` rows."
  def qualifications(%Member{} = member, now) do
    MemberQualificationAward
    |> join(:inner, [a], q in assoc(a, :qualification))
    |> where([a, q], a.member_id == ^member.id and q.team_id == ^member.team_id)
    |> preload([a, q], qualification: q)
    |> Repo.all()
    |> qualification_rows(now)
  end

  @doc """
  The member's awards as one row per qualification, `%{award:, earlier:,
  first_started_at:, status:, days_left:}`: the latest award (no end is the latest, else
  the one that ends last; a tie goes to the one that started last), the ones it replaced,
  newest first, when the first one started, `:expiring`, `:current`, or `:expired`, and
  `Service.Convert.days_until/2` its end (nil with no end). Expiring is within the app's one window,
  `BuildGroupRulePreview.expiring_days/0`.

  Current rows come first, soonest end first and no end last, then expired ones, most
  recent first. No groups (decided 2026-10-20): most members have nothing expiring, and
  headings over 1 or 2 rows were noise.
  """
  def qualification_rows(awards, now) do
    {expired, current} =
      awards
      |> Enum.group_by(& &1.qualification_id)
      |> Enum.map(fn {_id, awards} -> row(awards, now) end)
      |> Enum.split_with(&(&1.status == :expired))

    sort_rows(current, :asc) ++ sort_rows(expired, :desc)
  end

  defp row(awards, now) do
    [latest | earlier] = Enum.sort_by(awards, &latest_key/1, :desc)
    starts = awards |> Enum.map(& &1.starts_at) |> Enum.reject(&is_nil/1)

    %{
      award: latest,
      earlier: earlier,
      first_started_at: if(starts != [], do: Enum.min(starts, DateTime)),
      status: status(latest, now),
      days_left: latest.ends_at && Service.Convert.days_until(latest.ends_at, now)
    }
  end

  # The same rule as the Expires cell, so a muted row and its badge agree.
  defp status(award, now) do
    case BuildGroupRulePreview.expiry(award.ends_at, now) do
      :expired -> :expired
      nil -> :current
      _days_left -> :expiring
    end
  end

  defp sort_rows(rows, order),
    do: Enum.sort_by(rows, &{end_key(&1.award), &1.award.qualification.title}, order)

  # Sorts awards by end, with no end after every date.
  defp end_key(%{ends_at: nil}), do: {1, 0}
  defp end_key(%{ends_at: ends_at}), do: {0, DateTime.to_unix(ends_at)}

  # The latest award ends last; among ones with no end, D4H often holds the same
  # qualification twice, so the one that started last wins.
  defp latest_key(award), do: {end_key(award), unix(award.starts_at)}

  defp unix(nil), do: 0
  defp unix(datetime), do: DateTime.to_unix(datetime)

  defp attended_query(member, now), do: member_query(member, &Attendance.attended(&1, now))

  defp member_query(member, scope) do
    Attendance
    |> where([at], at.member_id == ^member.id)
    |> scope.()
    |> where([activity: ac], ac.team_id == ^member.team_id)
  end
end
