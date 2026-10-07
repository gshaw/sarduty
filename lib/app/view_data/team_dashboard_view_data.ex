defmodule App.ViewData.TeamDashboardViewData do
  @moduledoc """
  The team dashboard's reads (#205). `build/2` is the top half: what is coming up and
  the counts behind "Needs attention". `chart_rows/2` is the lower half, the team's year,
  which the page loads after the rest.
  """
  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Group
  alias App.Model.GroupRuleClause
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Team
  alias App.Operation.BuildGroupRulePreview
  alias App.Operation.SyncD4HChanges
  alias App.Repo
  alias App.ViewData.TeamAttention
  alias App.ViewModel.TaxCreditLetterFilterViewModel

  # NextUp shows an activity this close to starting, or this long into one still running.
  @next_up_hours 12
  @coming_up_days 14
  @coming_up_count 5

  def build(%Team{} = team, now \\ DateTime.utc_now()) do
    refresh_result = refresh_result_value(team, refresh_job_active?(team))
    {next_up, coming_up} = team |> agenda_activities(now) |> agenda(now)

    %{
      refreshed_at: team.d4h_refreshed_at,
      refresh_result: refresh_result,
      next_up: next_up,
      coming_up: coming_up,
      attention: team |> attention_rows(refresh_result, now) |> TeamAttention.items(now)
    }
  end

  defp attention_rows(team, refresh_result, now) do
    %{
      timezone: team.timezone,
      refresh: refresh_row(team, refresh_result),
      draft_count: count_recent_drafts(team, now),
      expiring_days: BuildGroupRulePreview.expiring_days(),
      expiring_count: count_expiring(team, now),
      missing_details_count: count_missing_details(team, now),
      group_change_count: count_group_changes(team, now),
      letters: letters_row(team, now)
    }
  end

  @doc """
  Splits activities into NextUp and Coming up. NextUp is the first one starting within
  #{@next_up_hours} hours, or started less than #{@next_up_hours} hours ago and not
  finished. Coming up is the next #{@coming_up_count} starting within #{@coming_up_days}
  days, without NextUp.
  """
  def agenda(activities, now) do
    activities = Enum.sort_by(activities, & &1.started_at, DateTime)
    next_up = Enum.find(activities, &next_up?(&1, now))
    until = DateTime.add(now, @coming_up_days, :day)

    coming_up =
      activities
      |> Enum.filter(fn activity ->
        activity != next_up and DateTime.after?(activity.started_at, now) and
          DateTime.before?(activity.started_at, until)
      end)
      |> Enum.take(@coming_up_count)

    {next_up, coming_up}
  end

  defp next_up?(activity, now) do
    soon = DateTime.add(now, @next_up_hours, :hour)
    lately = DateTime.add(now, -@next_up_hours, :hour)

    not DateTime.after?(activity.started_at, soon) and
      DateTime.after?(activity.started_at, lately) and
      DateTime.after?(activity.finished_at, now)
  end

  defp agenda_activities(team, now) do
    from = DateTime.add(now, -@next_up_hours, :hour)
    until = DateTime.add(now, @coming_up_days, :day)

    Activity
    |> where([a], a.team_id == ^team.id)
    |> Activity.not_deleted()
    |> where([a], a.started_at >= type(^naive(from), :naive_datetime))
    |> where([a], a.started_at < type(^naive(until), :naive_datetime))
    |> order_by([a], asc: a.started_at)
    |> Repo.all()
  end

  defp refresh_result_value(team, true) do
    if is_binary(team.d4h_refresh_result) and team.d4h_refresh_result != "OK" do
      team.d4h_refresh_result
    else
      "Refreshing"
    end
  end

  defp refresh_result_value(team, false), do: team.d4h_refresh_result

  defp refresh_job_active?(team) do
    Oban.Job
    |> where([j], j.worker == "App.Worker.RefreshTeamDataWorker")
    |> where([j], j.state in ["available", "scheduled", "executing", "retryable"])
    |> where([j], fragment("json_extract(?, '$.team_id') = ?", j.args, ^team.id))
    |> Repo.exists?()
  end

  defp refresh_row(team, refresh_result) do
    case Team.refresh_state(refresh_result) do
      :failed ->
        %{state: :failed, message: String.replace_prefix(refresh_result, "Error: ", "")}

      state ->
        if SyncD4HChanges.key_rejected?(team),
          do: %{state: :key_rejected, message: nil},
          else: %{state: state, message: nil}
    end
  end

  # Finished in the last 30 days and still a draft in D4H.
  defp count_recent_drafts(team, now) do
    Activity
    |> where([a], a.team_id == ^team.id and a.is_published == false)
    |> Activity.not_deleted()
    |> Activity.finished_recently(now)
    |> Repo.aggregate(:count)
  end

  defp count_expiring(team, now) do
    until = DateTime.add(now, BuildGroupRulePreview.expiring_days(), :day)
    team.id |> MemberQualificationAward.expiring(now, until) |> length()
  end

  defp count_missing_details(team, now) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> Member.current_query(now)
    |> Member.missing_details_query()
    |> Repo.aggregate(:count)
  end

  # Adds and removes waiting across every group with a rule. A rule naming a deleted
  # qualification plans nothing, and the groups page shows it as broken.
  defp count_group_changes(team, now) do
    ruled_group_ids =
      GroupRuleClause
      |> where([c], c.team_id == ^team.id)
      |> distinct(true)
      |> select([c], c.d4h_group_id)

    Group
    |> where([g], g.team_id == ^team.id and g.d4h_group_id in subquery(ruled_group_ids))
    |> Repo.all()
    |> Enum.map(fn group ->
      preview = BuildGroupRulePreview.for_group(team, group, now)
      length(preview.to_add) + length(preview.to_remove)
    end)
    |> Enum.sum()
  end

  # Only counted from January to April, since the hours count reads a year of attendance.
  defp letters_row(team, now) do
    if TeamAttention.letter_season?(now, team.timezone) do
      year = Service.YearRange.year_in(now, team.timezone) - 1
      filter = %TaxCreditLetterFilterViewModel{year: year, filter: "any", sort: "total"}

      count =
        team
        |> TaxCreditLetterFilterViewModel.find_all(filter, now)
        |> Enum.count(&is_nil(&1.tax_credit_letter_id))

      %{year: year, count: count}
    end
  end

  @doc """
  The rows the dashboard's stats, charts, and map are drawn from, as of `now`:
  activities in the last 2 years, attendance since January 1 last year, and current
  members. `TeamDashboardCharts.shape/2` turns them into chart data.
  """
  def chart_rows(%Team{} = team, now \\ DateTime.utc_now()) do
    this_year = Service.YearRange.year_in(now, team.timezone)
    {last_year_start, _} = Service.YearRange.bounds(this_year - 1, team.timezone)

    %{
      now: now,
      year: this_year,
      activities: recent_activities(team, DateTime.add(now, -730, :day), now),
      attendance: attendance_rows(team, last_year_start, now),
      members: current_members(team, now)
    }
  end

  defp recent_activities(team, since, now) do
    Activity
    |> where([a], a.team_id == ^team.id)
    |> Activity.not_deleted()
    |> where([a], a.started_at >= type(^naive(since), :naive_datetime))
    |> where([a], a.started_at <= type(^naive(now), :naive_datetime))
    |> select([a], %{
      id: a.id,
      title: a.title,
      kind: a.activity_kind,
      started_at: a.started_at,
      coordinate: a.coordinate
    })
    |> Repo.all()
  end

  defp attendance_rows(team, since, now) do
    Attendance
    |> join(:inner, [at], a in assoc(at, :activity))
    |> join(:inner, [at], m in assoc(at, :member))
    |> where([_, a, m], a.team_id == ^team.id and m.team_id == ^team.id and is_nil(a.deleted_at))
    |> where([at], at.status == "attending")
    # `since` is already naive: YearRange.bounds/2 gives the year's start that way.
    |> where([_, a], a.started_at >= type(^since, :naive_datetime))
    |> where([_, a], a.started_at <= type(^naive(now), :naive_datetime))
    |> select([at, a], %{started_at: a.started_at, minutes: coalesce(at.duration_in_minutes, 0)})
    |> Repo.all()
  end

  defp current_members(team, now) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> Member.current_query(now)
    |> select([m], %{id: m.id, joined_at: m.joined_at})
    |> Repo.all()
  end

  # Stored times mix `…Z` and no zone; a bound with no zone compares right against both.
  defp naive(%DateTime{} = datetime),
    do: datetime |> DateTime.truncate(:second) |> DateTime.to_naive()
end
