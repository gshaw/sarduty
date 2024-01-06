defmodule App.ViewData.TeamDashboardViewData do
  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Repo

  def build(team) do
    %{
      member_count: count_members(team),
      activity_count: count_activities(team),
      attendance_count: count_attendances(team),
      refreshed_at: team.d4h_refreshed_at
    }
  end

  def count_members(team) do
    query = from m in Member, where: m.team_id == ^team.id, select: count(1)
    Repo.one(query)
  end

  def count_activities(team) do
    query = from a in Activity, where: a.team_id == ^team.id, select: count(1)
    Repo.one(query)
  end

  def count_attendances(team) do
    Attendance
    |> join(:left, [a], m in assoc(a, :member))
    |> where([_, m], m.team_id == ^team.id)
    |> select(count(1))
    |> Repo.one()
  end
end
