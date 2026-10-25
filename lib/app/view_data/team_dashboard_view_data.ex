defmodule App.ViewData.TeamDashboardViewData do
  @moduledoc """
  The team dashboard's reads (#205). `build/2` is the top half: what is coming up and
  the counts behind "Needs attention". `chart_rows/2` is the lower half, the team's year,
  which the page loads after the rest.
  """
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Certificate
  alias App.Model.ChangeSet
  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.BuildGroupRulePreview
  alias App.Operation.SyncD4HChanges
  alias App.Repo
  alias App.ViewData.TeamAttention
  alias App.ViewModel.MemberFilterViewModel
  alias App.ViewModel.TaxCreditLetterFilterViewModel

  # NextUp shows an activity this close to starting, or this long into one still running.
  @next_up_hours 12
  @coming_up_days 14
  @coming_up_count 5

  @doc """
  The top half as of `now`. `attention?: false` leaves out Needs attention, which only
  team admins see, so a member's Dashboard doesn't count what nobody will read.
  """
  def build(%Team{} = team, now \\ DateTime.utc_now(), opts \\ []) do
    refresh_result = refresh_result_value(team, refresh_job_active?(team))
    {next_up, coming_up} = team |> agenda_activities(now) |> agenda(now)

    %{
      refreshed_at: team.d4h_refreshed_at,
      refresh_result: refresh_result,
      next_up: next_up,
      coming_up: coming_up,
      attention: attention(team, refresh_result, now, Keyword.get(opts, :attention?, true))
    }
  end

  defp attention(team, refresh_result, now, true),
    do: team |> attention_rows(refresh_result, now) |> TeamAttention.items(now)

  defp attention(_team, _refresh_result, _now, false), do: []

  defp attention_rows(team, refresh_result, now) do
    %{
      timezone: team.timezone,
      service: D4H.service(team),
      refresh: refresh_row(team, refresh_result),
      draft_count: count_recent_drafts(team, now),
      expiring_days: BuildGroupRulePreview.expiring_days(),
      expiring_count: count_expiring(team, now),
      missing_details_count: count_missing_details(team, now),
      not_seen: not_seen_row(team, now),
      group_change_count: count_group_changes(team, now),
      proposed_change_count: ChangeSet.count_waiting(team.id),
      chore_count: if(Team.chores?(team), do: Chore.count_waiting(team.id), else: 0),
      certificate_count:
        if(Team.certificates?(team), do: Certificate.count_waiting(team.id), else: 0),
      chores_to_send: chores_to_send(team),
      untagged: untagged_rows(team, now),
      letters: letters_row(team, now)
    }
  end

  defp chores_to_send(team),
    do: if(Team.chores?(team), do: ChoreEvent.count_to_send(team.id), else: 0)

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
    |> where([a], a.started_at >= ^from)
    |> where([a], a.started_at < ^until)
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
    |> Member.people_query()
    |> Member.missing_details_query()
    |> Repo.aggregate(:count)
  end

  # Nil when the team turned the item off in its settings. The count comes from the
  # Members list's own query, with the params the item links with, so they match (#366).
  defp not_seen_row(%Team{not_seen_days: nil}, _now), do: nil

  defp not_seen_row(%Team{not_seen_days: days} = team, now) do
    case watched_group(team) do
      :missing ->
        %{days: days, missing_group: true}

      group ->
        params = not_seen_params(team, group)

        %{
          days: days,
          group: group && group.title,
          params: params,
          count: MemberFilterViewModel.count(team, params, now)
        }
    end
  end

  defp watched_group(%Team{watch_d4h_group_id: nil}), do: nil

  defp watched_group(%Team{watch_d4h_group_id: id} = team),
    do: Group.get_by(team_id: team.id, d4h_group_id: id) || :missing

  @doc "The Members list's params for the team's attendance check, the home item's link."
  def not_seen_params(team, group) do
    [
      attended: "#{team.not_seen_days}",
      group: group && "#{group.id}",
      standing: Enum.join(team.watch_standings, ",")
    ]
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  # Adds and removes waiting across every group with rules. Rules with a problem plan
  # nothing, and the groups page shows them as broken.
  defp count_group_changes(team, now) do
    ruled_group_ids = GroupRule.ruled_d4h_group_ids_query(team.id)
    context = BuildGroupRulePreview.load(team)

    Group
    |> where([g], g.team_id == ^team.id and g.d4h_group_id in subquery(ruled_group_ids))
    |> Repo.all()
    |> Enum.map(fn group ->
      preview = BuildGroupRulePreview.preview(context, team, group, now)
      length(preview.to_add) + length(preview.to_remove)
    end)
    |> Enum.sum()
  end

  @doc """
  Published activities with no hours tag (#323), for teams that use the hours tags: ones
  with their primary or secondary tag among their tags. One row per open year,
  `%{year:, count:}`. Empty for other teams. An organization's Teams page counts them too
  (#512).
  """
  def untagged_rows(team, now) do
    hours_tags = Activity.hours_tags(team)

    if uses_hours_tags?(team, hours_tags) do
      now
      |> Service.Period.open_years(team.timezone)
      |> Enum.map(&%{year: &1, count: count_untagged(team, hours_tags, &1)})
    else
      []
    end
  end

  defp count_untagged(team, hours_tags, year) do
    Activity
    |> where([a], a.team_id == ^team.id and a.is_published == true)
    |> Activity.not_deleted()
    |> Activity.started_in(year, team.timezone)
    |> Activity.without_hours_tag(hours_tags)
    |> Repo.aggregate(:count)
  end

  defp uses_hours_tags?(team, hours_tags) do
    Tag
    |> where(
      [t],
      t.team_id == ^team.id and t.title in ^[hours_tags.primary, hours_tags.secondary]
    )
    |> Repo.exists?()
  end

  # Only counted from January to April, since the hours count reads a year of attendance.
  defp letters_row(team, now) do
    if Service.Period.letter_season?(now, team.timezone) do
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
    |> where([a], a.started_at >= ^since)
    |> where([a], a.started_at <= ^now)
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
    now
    |> Attendance.attended()
    |> join(:inner, [at], m in assoc(at, :member))
    |> where([activity: a], a.team_id == ^team.id and a.started_at >= ^since)
    |> where([at, ..., m], m.team_id == ^team.id)
    |> select([at, activity: a], %{
      started_at: a.started_at,
      minutes: coalesce(at.duration_in_minutes, 0)
    })
    |> Repo.all()
  end

  defp current_members(team, now) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> Member.current_query(now)
    |> Member.people_query()
    |> select([m], %{id: m.id, joined_at: m.joined_at})
    |> Repo.all()
  end
end
