defmodule App.ViewData.MemberRecords do
  import Ecto.Query

  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Operation.BuildGroupRulePreview
  alias App.Operation.CountTaxCreditHours
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

  @doc "Primary, secondary, and total minutes in `year`, counted as the letter counts them."
  def hours(%Member{} = member, year, now) do
    member.team
    |> CountTaxCreditHours.call(year, [member.id], now)
    |> CountTaxCreditHours.get(member.id)
  end

  @doc "The member's attended rows that started in `year`, newest first, with the activity."
  def attendances(%Member{} = member, year, now) do
    member
    |> attended_query(now)
    |> Attendance.started_in(year, member.team.timezone)
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

  @doc "How long the member was there: their own times, else D4H's duration."
  def minutes(%{started_at: %DateTime{} = started_at, finished_at: %DateTime{} = finished_at}),
    do: max(0, div(DateTime.diff(finished_at, started_at), 60))

  def minutes(%{duration_in_minutes: minutes}), do: minutes || 0

  @doc "The member's qualifications, grouped by `group_awards/2`."
  def qualifications(%Member{} = member, now) do
    MemberQualificationAward
    |> join(:inner, [a], q in assoc(a, :qualification))
    |> where([a, q], a.member_id == ^member.id and q.team_id == ^member.team_id)
    |> preload([a, q], qualification: q)
    |> Repo.all()
    |> group_awards(now)
  end

  @groups [:within_60_days, :within_180_days, :later, :never, :expired]

  @doc """
  The member's awards as `[{group, [row]}]`, one row per qualification, in the order of
  `#{inspect(@groups)}`, with empty groups left out. 60 days is the app's one expiring
  window (`BuildGroupRulePreview.expiring_days/0`) and 180 the longest choice on the
  team's expiring view.

  Each row is `%{award:, earlier:, first_started_at:}`: the latest award (no end is the
  latest, else the one that ends last), the ones it replaced, newest first, and when the
  first one started. Current groups come soonest end first, the expired most recent first.
  """
  def group_awards(awards, now) do
    rows =
      awards
      |> Enum.group_by(& &1.qualification_id)
      |> Enum.map(fn {_id, awards} -> row(awards) end)
      |> Enum.group_by(&group(&1.award, now))

    for group <- @groups, rows = rows[group], do: {group, sort_rows(rows, group)}
  end

  defp row(awards) do
    [latest | earlier] = Enum.sort_by(awards, &end_key/1, :desc)
    starts = awards |> Enum.map(& &1.starts_at) |> Enum.reject(&is_nil/1)

    %{
      award: latest,
      earlier: earlier,
      first_started_at: if(starts != [], do: Enum.min(starts, DateTime))
    }
  end

  defp group(%{ends_at: nil}, _now), do: :never

  # Within a window means ending on or before its last moment, as the team's expiring
  # view counts it.
  defp group(%{ends_at: ends_at} = award, now) do
    within? = &(not DateTime.after?(ends_at, DateTime.add(now, &1, :day)))

    cond do
      MemberQualificationAward.expired?(award, now) -> :expired
      within?.(BuildGroupRulePreview.expiring_days()) -> :within_60_days
      within?.(180) -> :within_180_days
      true -> :later
    end
  end

  defp sort_rows(rows, group) do
    order = if group == :expired, do: :desc, else: :asc
    Enum.sort_by(rows, &{end_key(&1.award), &1.award.qualification.title}, order)
  end

  # Sorts awards by end, with no end after every date.
  defp end_key(%{ends_at: nil}), do: {1, 0}
  defp end_key(%{ends_at: ends_at}), do: {0, DateTime.to_unix(ends_at)}

  @doc """
  Attendances by the month they started in the team's time zone, as `[{first_day,
  [attendance]}]`, keeping the order they came in.
  """
  def by_month(attendances, timezone) do
    attendances
    |> Enum.chunk_by(&month(&1.started_at, timezone))
    |> Enum.map(&{month(hd(&1).started_at, timezone), &1})
  end

  defp month(datetime, timezone) do
    date = datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
    Date.beginning_of_month(date)
  end

  defp attended_query(member, now), do: member_query(member, &Attendance.attended(&1, now))

  defp member_query(member, scope) do
    Attendance
    |> where([at], at.member_id == ^member.id)
    |> scope.()
    |> where([activity: ac], ac.team_id == ^member.team_id)
  end
end
