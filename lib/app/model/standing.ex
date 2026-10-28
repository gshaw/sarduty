defmodule App.Model.Standing do
  @moduledoc """
  A member's standing (#366, #514), the one home for its order: Retired, Not a person,
  Retiring, Away, then Active. The first that applies wins.

  - Retired comes from D4H, as of `now` (Member.current?/2).
  - Not a person is a team admin's switch in SAR Duty.
  - Retiring is membership of the team's Retiring group, a D4H group named in team
    settings. Never stored: read from `group_members` when needed. A retiring member is
    no longer a member: they can't log in and nothing counts or contacts them
    (docs/members.md, Retiring).
  - Away is a current away period, a team admin's record in SAR Duty.
  - Active is the absence of the rest.

  of/5 works it out for one member, pure. join/3 and dynamic/1 work it out in SQL for a
  member query, and a test keeps the two in agreement.
  """
  import Ecto.Query

  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.Team
  alias App.Repo

  @doc "Every standing, in the order the first that applies wins."
  def order, do: [:retired, :not_a_person, :retiring, :away, :active]

  @doc """
  Pure. The member's standing on `today`: `:retired`, `:not_a_person`, `:retiring`,
  `{:away, period}` for the current away period that ends last, or `:active`.
  `retiring?` is whether the member is in the team's Retiring group.
  """
  def of(member, periods, retiring?, %Date{} = today, now) do
    cond do
      not Member.current?(member, now) -> :retired
      member.not_a_person -> :not_a_person
      retiring? -> :retiring
      true -> away_or_active(periods, today)
    end
  end

  defp away_or_active(periods, today) do
    case periods
         |> Enum.filter(&MemberAwayPeriod.current?(&1, today))
         |> Enum.max_by(& &1.ends_on, Date, fn -> nil end) do
      nil -> :active
      period -> {:away, period}
    end
  end

  @doc "The member's standing today in the team's time zone."
  def today(%Member{} = member, %Team{} = team, now \\ DateTime.utc_now()) do
    retiring? = team |> retiring_ids() |> MapSet.member?(member.id)
    today = Service.Period.today(now, team.timezone)
    of(member, MemberAwayPeriod.for_member(member), retiring?, today, now)
  end

  @doc "Each of `members`' standing today, by id: of/5 with the team's data loaded once."
  def by_member(%Team{} = team, members, now) do
    today = Service.Period.today(now, team.timezone)
    periods = team.id |> MemberAwayPeriod.get_all_for_team() |> Enum.group_by(& &1.member_id)
    retiring = retiring_ids(team)

    Map.new(members, fn member ->
      retiring? = MapSet.member?(retiring, member.id)
      {member.id, of(member, Map.get(periods, member.id, []), retiring?, today, now)}
    end)
  end

  @doc """
  The ids of the team's members in its Retiring group, as a query: none when the team
  has no Retiring group, or it was deleted. Retired members in it are left to of/5.
  """
  def retiring_ids_query(%Team{} = team),
    do: team |> retiring_memberships() |> select([gm], gm.member_id)

  defp retiring_memberships(%Team{retiring_d4h_group_id: nil}),
    do: where(GroupMember, false)

  defp retiring_memberships(%Team{} = team) do
    from gm in GroupMember,
      join: g in Group,
      on: g.id == gm.group_id,
      where: g.team_id == ^team.id and g.d4h_group_id == ^team.retiring_d4h_group_id
  end

  @doc """
  The ids of the team's members whose standing is Retiring, as a query: current on `now`,
  people, and in the Retiring group. The Dashboard's counts and Equipment's "With
  retiring members" read this, so they agree.
  """
  def retiring_member_ids_query(%Team{} = team, now) do
    Member
    |> where([m], m.team_id == ^team.id and m.id in subquery(retiring_ids_query(team)))
    |> Member.current_query(now)
    |> Member.people_query()
    |> select([m], m.id)
  end

  @doc """
  The ids of members in their own team's Retiring group, on every team. Logins read it:
  a retiring member can't log in, as a team admin or a member.
  """
  def all_retiring_ids_query do
    from gm in GroupMember,
      join: g in Group,
      on: g.id == gm.group_id,
      join: t in Team,
      on: t.id == g.team_id and g.d4h_group_id == t.retiring_d4h_group_id,
      select: gm.member_id
  end

  @doc "retiring_ids_query/1 as a set."
  def retiring_ids(%Team{} = team),
    do: team |> retiring_ids_query() |> Repo.all() |> MapSet.new()

  @doc """
  Joins what dynamic/1 reads to a query on members: `away`, each member's `away_until`
  on `today`, and `retiring`, a row for each member in the Retiring group.
  """
  def join(query, %Team{} = team, %Date{} = today) do
    from(m in query,
      left_join: w in subquery(MemberAwayPeriod.away_query(team, today)),
      as: :away,
      on: m.id == w.member_id,
      left_join: r in subquery(retiring_rows(team)),
      as: :retiring,
      on: m.id == r.member_id
    )
  end

  defp retiring_rows(team),
    do:
      team |> retiring_memberships() |> distinct(true) |> select([gm], %{member_id: gm.member_id})

  @doc """
  of/5 in SQL, as the standing's name: "retired", "not_a_person", "retiring", "away", or
  "active". The query needs join/3.
  """
  def dynamic(now) do
    current = Member.current_dynamic(now)

    dynamic(
      [m, away: w, retiring: r],
      fragment(
        "CASE WHEN NOT (?) THEN 'retired' WHEN ? THEN 'not_a_person' WHEN ? IS NOT NULL THEN 'retiring' WHEN ? IS NOT NULL THEN 'away' ELSE 'active' END",
        ^current,
        m.not_a_person,
        r.member_id,
        w.away_until
      )
    )
  end

  @doc "The kind of a standing, without the away period: `:away` for `{:away, period}`."
  def kind({:away, _period}), do: :away
  def kind(standing) when is_atom(standing), do: standing

  @doc """
  A standing as `team_admin?` sees it (#440). To a member, someone away is active: away
  periods are team admins' own records, and away is often leave. Every other standing
  shows as it is: Retiring comes from a D4H group members already see on the Groups tab.
  Every page that shows another member's standing passes it through here.
  """
  def visible({:away, _period}, false = _team_admin?), do: :active
  def visible(standing, _team_admin?), do: standing

  @doc ~s{The standing as text: "Active", "Away until March 1, 2027 (Parental leave)", "Retiring", "Not a person", or "Retired".}
  def text(:active), do: "Active"
  def text(:retiring), do: "Retiring"
  def text(:not_a_person), do: "Not a person"
  def text(:retired), do: "Retired"

  def text({:away, period}),
    do: "Away until #{Service.Format.date_long(period.ends_on)} (#{period.reason})"
end
