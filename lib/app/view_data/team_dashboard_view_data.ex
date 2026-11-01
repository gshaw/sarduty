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
  alias App.Model.AttendanceScan
  alias App.Model.AttentionSnooze
  alias App.Model.Certificate
  alias App.Model.Chore
  alias App.Model.ChoreEvent
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.NoShow
  alias App.Model.Standing
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
  `member:` is the team admin reading it, whose own chores and certificates wait for
  someone else.
  `attention` is the items shown, `more_attention` the ones past the page's limit, and
  `snoozed` the ones a team admin snoozed (#751), each with the name of who did,
  `snoozed_by`.
  """
  def build(%Team{} = team, now \\ DateTime.utc_now(), opts \\ []) do
    refresh_result = refresh_result_value(team, refresh_job_active?(team))
    {next_up, coming_up} = team |> agenda_activities(now) |> agenda(now)

    attention =
      attention(team, refresh_result, now, Keyword.get(opts, :attention?, true), opts[:member])

    Map.merge(attention, %{
      refreshed_at: team.d4h_refreshed_at,
      refresh_result: refresh_result,
      next_up: next_up,
      coming_up: coming_up
    })
  end

  @doc """
  Every Needs attention item a team admin would see, without the page's limit: for an
  agent's needs_attention tool (#595) and for snoozing one (#751). Snoozed items come
  last, each with its `snooze`. Its chores and certificates are every one waiting, a team
  admin's own too.
  """
  def attention_items(%Team{} = team, now \\ DateTime.utc_now()) do
    refresh_result = refresh_result_value(team, refresh_job_active?(team))

    %{shown: shown, snoozed: snoozed} =
      team
      |> attention_rows(refresh_result, now, nil)
      |> TeamAttention.items(now, AttentionSnooze.get_all(team), :all)

    shown ++ snoozed
  end

  defp snoozed_by(team, snooze, now), do: Member.name_for_user(team, snooze.user, now)

  defp attention(team, refresh_result, now, true, member) do
    %{shown: shown, more: more, snoozed: snoozed} =
      team
      |> attention_rows(refresh_result, now, member)
      |> TeamAttention.items(now, AttentionSnooze.get_all(team))

    %{
      attention: shown,
      more_attention: more,
      snoozed: Enum.map(snoozed, &Map.put(&1, :snoozed_by, snoozed_by(team, &1.snooze, now)))
    }
  end

  defp attention(_team, _refresh_result, _now, false, _member),
    do: %{attention: [], more_attention: [], snoozed: []}

  defp attention_rows(team, refresh_result, now, member) do
    %{
      timezone: team.timezone,
      service: D4H.service(team),
      refresh: refresh_row(team, refresh_result),
      names: Map.take(team, [:name, :abbreviated_name]),
      contacts?: Member.get_team_contacts(team, now) != [],
      draft_ids: recent_draft_ids(team, now),
      missing_fields_ids: missing_fields_ids(team, now),
      expiring_days: BuildGroupRulePreview.expiring_days(),
      expiring_ids: expiring_ids(team, now),
      missing_details_ids: missing_details_ids(team, now),
      not_seen: not_seen_row(team, now),
      retiring: retiring_row(team, now),
      group_change_count: count_group_changes(team, now),
      chore_count: if(Team.chores?(team), do: Chore.count_to_accept(team, member, now), else: 0),
      certificate_count:
        if(Team.certificates?(team),
          do: Certificate.count_to_accept(team, member, now),
          else: 0
        ),
      chores_to_send: chores_to_send(team),
      attendance_to_send: attendance_to_send(team, now),
      no_shows: no_shows(team, now),
      untagged: untagged_rows(team, now),
      two_hours_tags: two_hours_tags_rows(team, now),
      letters: letters_row(team, now)
    }
  end

  defp chores_to_send(team),
    do: if(Team.chores?(team), do: ChoreEvent.count_to_send(team.id), else: 0)

  # No-shows wait a week for a follow-up, then drop off (#650): following up is a habit
  # for the week after, not a list to clear.
  @no_show_days 7

  defp no_shows(team, now),
    do: NoShow.to_follow_up(team, DateTime.add(now, -@no_show_days, :day), now)

  @attendance_to_send_days 30

  @doc """
  Activities with attendance a team admin hasn't sent (#475): not deleted, not published,
  finished in the last #{@attendance_to_send_days} days, with a scan since their
  attendance was last sent (Activity.mark_attendance_sent/2), or never sent. Members take
  attendance on their own, so nothing else tells a team admin it's there. A published
  activity's attendance is final: it can't take a send, and whoever published it has
  checked it. The limit keeps a scan nobody means to send from waiting forever. Oldest
  first, each `%{id:, title:}`.
  """
  def attendance_to_send(%Team{} = team, now) do
    now = DateTime.truncate(now, :second)
    since = DateTime.add(now, -@attendance_to_send_days, :day)

    Activity
    |> where([a], a.team_id == ^team.id)
    |> Activity.not_deleted()
    |> where([a], not a.is_published)
    |> where([a], a.finished_at >= ^since and a.finished_at <= ^now)
    |> join(:inner, [a], s in AttendanceScan, on: s.activity_id == a.id and s.team_id == ^team.id)
    |> where([a, s], is_nil(a.attendance_sent_at) or s.inserted_at > a.attendance_sent_at)
    |> group_by([a], a.id)
    |> order_by([a], asc: a.started_at, asc: a.id)
    |> select([a], %{id: a.id, title: a.title})
    |> Repo.all()
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
        activity != next_up and not Activity.started?(activity, now) and
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

  # The items that can be snoozed (#751) read ids rather than a count, sorted, so a
  # snooze can tell who is new behind the item.

  # Finished in the last 30 days and still a draft in D4H.
  defp recent_draft_ids(team, now) do
    Activity
    |> where([a], a.team_id == ^team.id and a.is_published == false)
    |> Activity.not_deleted()
    |> Activity.finished_recently(now, team.timezone)
    |> ids()
  end

  defp ids(query), do: query |> select([r], r.id) |> order_by([r], r.id) |> Repo.all()

  # Finished drafts with a required custom field left empty (#681): D4H won't publish
  # them until it's filled in.
  defp missing_fields_ids(team, now) do
    Activity
    |> where([a], a.team_id == ^team.id and a.is_published == false and a.finished_at < ^now)
    |> Activity.not_deleted()
    |> Activity.missing_required_fields()
    |> ids()
  end

  # One row per member and qualification; its newest award stands for the row.
  defp expiring_ids(team, now) do
    until = DateTime.add(now, BuildGroupRulePreview.expiring_days(), :day)

    team.id
    |> MemberQualificationAward.expiring(now, until)
    |> Enum.map(& &1.award_id)
    |> Enum.sort()
  end

  defp missing_details_ids(team, now) do
    Member
    |> where([m], m.team_id == ^team.id)
    |> Member.current_query(now)
    |> Member.counted_query()
    |> Member.missing_details_query()
    |> ids()
  end

  # Nil when the team turned the item off in its settings. The ids come from the Members
  # list's own query, with the params the item links with, so they match (#366).
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
          ids: MemberFilterViewModel.ids(team, params, now)
        }
    end
  end

  # Retiring members (#514), counted apart by whether they still hold the team's items,
  # and those D4H still lets log in.
  # Nil for a team with no Retiring group.
  defp retiring_row(%Team{retiring_d4h_group_id: nil}, _now), do: nil

  defp retiring_row(%Team{retiring_d4h_group_id: id} = team, now) do
    if Group.get_by(team_id: team.id, d4h_group_id: id) do
      ids = Standing.retiring_member_ids_query(team, now)
      counts = EquipmentItem.held_counts(team, ids)

      %{
        holding: map_size(counts),
        holding_ids: counts |> Map.keys() |> Enum.sort(),
        items: counts |> Map.values() |> Enum.sum(),
        clear_ids: ids |> Repo.all() |> Enum.reject(&Map.has_key?(counts, &1)) |> Enum.sort(),
        d4h_access:
          Member
          |> where([m], m.id in subquery(ids))
          |> Member.d4h_access_query(true)
          |> Repo.aggregate(:count)
      }
    else
      %{missing_group: true}
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
  `%{year:, count:, ids:}`. Empty for other teams. An organization's Teams page counts them too
  (#512).
  """
  def untagged_rows(team, now) do
    hours_tags = Activity.hours_tags(team)

    if uses_hours_tags?(team, hours_tags) do
      now
      |> Service.Period.open_years(team.timezone)
      |> Enum.map(&untagged_row(team, hours_tags, &1))
    else
      []
    end
  end

  defp untagged_row(team, hours_tags, year) do
    ids =
      Activity
      |> where([a], a.team_id == ^team.id and a.is_published == true)
      |> Activity.not_deleted()
      |> Activity.started_in(year, team.timezone)
      |> Activity.without_hours_tag(hours_tags)
      |> ids()

    %{year: year, count: length(ids), ids: ids}
  end

  @doc """
  Activities with two hours tags (#763), drafts too, since letters count drafts.
  One row per open year, `%{year:, primary:, secondary:, ids:}`: how many count for each
  kind (`Activity.counts_as/2`), and their ids, sorted, for snoozing (#751).
  """
  def two_hours_tags_rows(team, now) do
    hours_tags = Activity.hours_tags(team)

    now
    |> Service.Period.open_years(team.timezone)
    |> Enum.map(fn year ->
      rows =
        Activity
        |> where([a], a.team_id == ^team.id)
        |> Activity.not_deleted()
        |> Activity.started_in(year, team.timezone)
        |> Activity.with_two_hours_tags(hours_tags)
        |> select([a], {a.id, a.tags})
        |> order_by([a], a.id)
        |> Repo.all()

      kinds =
        Enum.frequencies_by(rows, fn {_id, tags} -> Activity.counts_as(tags, hours_tags) end)

      %{
        year: year,
        primary: kinds[:primary] || 0,
        secondary: kinds[:secondary] || 0,
        ids: Enum.map(rows, &elem(&1, 0))
      }
    end)
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
    |> Member.counted_query()
    |> select([m], %{id: m.id, joined_at: m.joined_at})
    |> Repo.all()
  end
end
