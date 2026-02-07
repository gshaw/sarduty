defmodule App.ViewData.TeamDashboardViewData do
  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Repo

  def build(team) do
    refreshing? = refresh_job_active?(team)

    %{
      member_count: count_members(team),
      activity_count: count_activities(team),
      attendance_count: count_attendances(team),
      qualification_count: count_qualifications(team),
      qualification_award_count: count_qualification_awards(team),
      refreshed_at: team.d4h_refreshed_at,
      refresh_result: if(refreshing?, do: "Refreshing", else: team.d4h_refresh_result)
    }
  end

  defp refresh_job_active?(team) do
    Oban.Job
    |> where([j], j.worker == "App.Worker.RefreshTeamDataWorker")
    |> where([j], j.state in ["available", "scheduled", "executing", "retryable"])
    |> where([j], fragment("json_extract(?, '$.team_id') = ?", j.args, ^team.id))
    |> select([j], count(j.id))
    |> Repo.one()
    |> Kernel.>(0)
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

  def count_qualifications(team) do
    query = from q in Qualification, where: q.team_id == ^team.id, select: count(1)
    Repo.one(query)
  end

  def count_qualification_awards(team) do
    MemberQualificationAward
    |> join(:left, [a], m in assoc(a, :member))
    |> where([_, m], m.team_id == ^team.id)
    |> select(count(1))
    |> Repo.one()
  end
end
