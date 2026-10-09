defmodule App.ViewData.MemberRecords do
  import Ecto.Query

  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Operation.BuildGroupRulePreview
  alias App.Operation.CountTaxCreditHours
  alias App.Repo

  # A member's own records, for their page (#156, stage 2): hours and attended activities
  # for one year, and their qualifications. Every query filters by the member and their
  # team. Expects the member with its team, as Member.get_logins/2 returns it.

  @doc "The years the member attended something in, and this year, newest first."
  def years(%Member{} = member, now) do
    this_year = Service.YearRange.year_in(now, member.team.timezone)

    member
    |> attended_query()
    |> Attendance.years(member.team.timezone)
    |> then(&[this_year | &1])
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  @doc "Primary, secondary, and total minutes in `year`, counted as the letter counts them."
  def hours(%Member{} = member, year) do
    member.team
    |> CountTaxCreditHours.call(year, [member.id])
    |> CountTaxCreditHours.get(member.id)
  end

  @doc "The member's attended rows that started in `year`, newest first, with the activity."
  def attendances(%Member{} = member, year) do
    member
    |> attended_query()
    |> Attendance.started_in(year, member.team.timezone)
    |> order_by([at], desc: at.started_at)
    |> preload([at, ac], activity: ac)
    |> Repo.all()
  end

  @doc "How long the member was there: their own times, else D4H's duration."
  def minutes(%{started_at: %DateTime{} = started_at, finished_at: %DateTime{} = finished_at}),
    do: max(0, div(DateTime.diff(finished_at, started_at), 60))

  def minutes(%{duration_in_minutes: minutes}), do: minutes || 0

  @doc "The member's qualifications, split by `split_awards/3`."
  def qualifications(%Member{} = member, now) do
    MemberQualificationAward
    |> join(:inner, [a], q in assoc(a, :qualification))
    |> where([a, q], a.member_id == ^member.id and q.team_id == ^member.team_id)
    |> preload([a, q], qualification: q)
    |> Repo.all()
    |> split_awards(now, BuildGroupRulePreview.expiring_days())
  end

  @doc """
  The latest award of each qualification, as `%{current: […], expired: […]}`. An award
  with no end is the latest; otherwise the one that ends last. Current ones come soonest
  to expire first, with no end last, and each is `:expiring` when it ends within
  `soon_days`. Expired ones come most recently expired first.
  """
  def split_awards(awards, now, soon_days) do
    soon = DateTime.add(now, soon_days, :day)

    {expired, current} =
      awards
      |> Enum.group_by(& &1.qualification_id)
      |> Enum.map(fn {_id, awards} -> Enum.max_by(awards, &end_key/1) end)
      |> Enum.split_with(&MemberQualificationAward.expired?(&1, now))

    %{
      current:
        current |> sort_by_end(:asc) |> Enum.map(&%{award: &1, expiring?: expiring?(&1, soon)}),
      expired: expired |> sort_by_end(:desc) |> Enum.map(&%{award: &1, expiring?: false})
    }
  end

  defp sort_by_end(awards, order),
    do: Enum.sort_by(awards, &{end_key(&1), &1.qualification.title}, order)

  # Sorts awards by end, with no end after every date.
  defp end_key(%{ends_at: nil}), do: {1, 0}
  defp end_key(%{ends_at: ends_at}), do: {0, DateTime.to_unix(ends_at)}

  defp expiring?(%{ends_at: nil}, _soon), do: false
  defp expiring?(%{ends_at: ends_at}, soon), do: not DateTime.after?(ends_at, soon)

  defp attended_query(member) do
    Attendance
    |> join(:inner, [at], ac in assoc(at, :activity))
    |> where([at, ac], at.member_id == ^member.id and ac.team_id == ^member.team_id)
    |> where([at, ac], at.status == "attending" and is_nil(ac.deleted_at))
  end
end
