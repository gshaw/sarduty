defmodule App.ViewData.MemberMilestones do
  @moduledoc """
  Milestones (#389) loaded for a page: one member's, for Your membership and a team
  admin's member sidebar, or every current member's, for the team's Milestones page.
  Worked out from `App.ViewData.Milestones.build/5` on each load, nothing stored:
  about 130 ms for a team with 22,000 attended rows (dev copy, 2026-10-23), and a stored
  copy would go stale whenever attendance, `joined_at`, or an away period changes.
  """

  import Ecto.Query

  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Repo
  alias App.ViewData.MemberRecords
  alias App.ViewData.Milestones

  @doc """
  The member's milestones, newest first. Pass their attended rows when the page has
  them already. Expects the member with its team.
  """
  def for_member(%Member{} = member, now, attended \\ nil) do
    (attended || MemberRecords.attended(member, now))
    |> Milestones.build(
      member.joined_at,
      MemberAwayPeriod.for_member(member),
      now,
      member.team.timezone
    )
  end

  @doc """
  Every current member's milestones, newest first, each with its `member`. Members by
  name on the same day.
  """
  def for_team(team, now) do
    attended = attended_by_member(team, now)
    away = away_by_member(team)

    Member
    |> where(team_id: ^team.id)
    |> Member.current_query(now)
    |> order_by(:name)
    |> Repo.all()
    |> Enum.flat_map(fn member ->
      attended
      |> Map.get(member.id, [])
      |> Milestones.build(member.joined_at, Map.get(away, member.id, []), now, team.timezone)
      |> Enum.map(&Map.put(&1, :member, member))
    end)
    |> Enum.sort_by(&Date.to_gregorian_days(&1.on), :desc)
  end

  defp attended_by_member(team, now) do
    Attendance
    |> Attendance.attended(now)
    |> where([activity: a], a.team_id == ^team.id)
    |> preload([activity: a], activity: a)
    |> Repo.all()
    |> Enum.group_by(& &1.member_id)
  end

  defp away_by_member(team) do
    MemberAwayPeriod
    |> where(team_id: ^team.id)
    |> Repo.all()
    |> Enum.group_by(& &1.member_id)
  end
end
