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
  the one that ends last), the ones it replaced, newest first, when the first one started,
  `:expiring`, `:current`, or `:expired`, and `Service.Convert.days_until/2` its end (nil
  with no end). Expiring is within the app's one window,
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
    [latest | earlier] = Enum.sort_by(awards, &end_key/1, :desc)
    starts = awards |> Enum.map(& &1.starts_at) |> Enum.reject(&is_nil/1)

    %{
      award: latest,
      earlier: earlier,
      first_started_at: if(starts != [], do: Enum.min(starts, DateTime)),
      status: status(latest, now),
      days_left: latest.ends_at && Service.Convert.days_until(latest.ends_at, now)
    }
  end

  defp status(%{ends_at: nil}, _now), do: :current

  # Within the window means ending on or before its last moment, as the team's expiring
  # view counts it.
  defp status(%{ends_at: ends_at} = award, now) do
    until = DateTime.add(now, BuildGroupRulePreview.expiring_days(), :day)

    cond do
      MemberQualificationAward.expired?(award, now) -> :expired
      DateTime.after?(ends_at, until) -> :current
      true -> :expiring
    end
  end

  defp sort_rows(rows, order),
    do: Enum.sort_by(rows, &{end_key(&1.award), &1.award.qualification.title}, order)

  # Sorts awards by end, with no end after every date.
  defp end_key(%{ends_at: nil}), do: {1, 0}
  defp end_key(%{ends_at: ends_at}), do: {0, DateTime.to_unix(ends_at)}

  defp attended_query(member, now), do: member_query(member, &Attendance.attended(&1, now))

  defp member_query(member, scope) do
    Attendance
    |> where([at], at.member_id == ^member.id)
    |> scope.()
    |> where([activity: ac], ac.team_id == ^member.team_id)
  end
end
