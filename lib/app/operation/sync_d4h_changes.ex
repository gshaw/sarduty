defmodule App.Operation.SyncD4HChanges do
  @moduledoc """
  Copies what changed in D4H since the last look, every 10 minutes (#163). The nightly
  full refresh, App.Operation.RefreshD4HData, stays as the safety net.

  One request per list, sorted by `updatedAt`, gives each list's total and newest
  change. When none moved, that's all. Otherwise small lists are fetched whole through
  the refresh's own stages, activities and attendance changed since the last look are
  fetched by date, and each touched activity's attendance is compared whole to catch
  deletes. When the attendance totals still differ, counts by year and then by month
  find one window to fetch again. plan/2 and windows_to_check/2 decide; call/2 fetches
  and writes.
  """

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.RefreshD4HData.CheckMemberPhotos
  alias App.Operation.RefreshD4HData.Progress
  alias App.Operation.RefreshD4HData.UpsertActivities
  alias App.Operation.RefreshD4HData.UpsertAttendances
  alias App.Operation.RefreshD4HData.UpsertGroupMemberships
  alias App.Operation.RefreshD4HData.UpsertGroups
  alias App.Operation.RefreshD4HData.UpsertMembers
  alias App.Operation.RefreshD4HData.UpsertQualificationAwards
  alias App.Operation.RefreshD4HData.UpsertQualifications
  alias App.Repo

  require Logger

  @lists ~w(members tags exercises events incidents attendance member-qualifications
            member-qualification-awards member-groups member-group-memberships)

  @activity_kinds ~w(exercises events incidents)
  @activity_kind %{"exercises" => "exercise", "events" => "event", "incidents" => "incident"}

  # Fetched whole when they change, in this order, since later ones point at earlier ones.
  @small_lists ~w(members member-qualifications member-qualification-awards member-groups
                  member-group-memberships)

  # Rows that were skipped for an unknown parent come in once the parent does.
  @dependents %{
    "members" => ["member-qualification-awards", "member-group-memberships"],
    "member-qualifications" => ["member-qualification-awards"],
    "member-groups" => ["member-group-memberships"]
  }

  # The cursor is the newest change D4H showed last time, less this overlap, so our
  # clock never matters and a row updated mid-sync is seen again.
  @overlap_seconds 5 * 60
  @start_of_time ~U[2000-01-01 00:00:00Z]
  @concurrency 4

  @doc """
  What to fetch, from the list heads the last sync saw and the ones D4H shows now. A
  head is `%{total_size: n, newest_updated_at: datetime}`.

  `:seed` when there is no previous look, `:unchanged` when no head moved. Otherwise a
  map: `lists` to fetch whole, in order; `activities`, by kind, with the `updated_after`
  cursor, whether to compare every id to find deletes (when the kind's own head moved),
  and whether its rows count as touched; and `attendance_since`, nil when attendance didn't
  move. A tag change refetches every activity, since activities store tag titles; those
  don't count as touched, or every activity's attendance would be fetched.
  """
  def plan(nil, _heads), do: :seed

  def plan(previous, heads) do
    case Enum.filter(@lists, &(Map.get(previous, &1) != Map.get(heads, &1))) do
      [] -> :unchanged
      changed -> plan_changed(previous, changed)
    end
  end

  defp plan_changed(previous, changed) do
    refetch = Enum.flat_map(changed, &[&1 | Map.get(@dependents, &1, [])])
    refetch_all? = "tags" in changed

    activities =
      for kind <- @activity_kinds, refetch_all? or kind in changed, into: %{} do
        since = since(previous[kind])

        {kind,
         %{
           updated_after: if(refetch_all?, do: @start_of_time, else: since),
           compare_ids?: kind in changed,
           touch?: not refetch_all?
         }}
      end

    %{
      changed: changed,
      lists: Enum.filter(@small_lists, &(&1 in refetch)),
      activities: activities,
      attendance_since: if("attendance" in changed, do: since(previous["attendance"]))
    }
  end

  defp since(%{newest_updated_at: %DateTime{} = at}), do: DateTime.add(at, -@overlap_seconds)
  defp since(_never_or_empty), do: @start_of_time

  @doc """
  The windows whose counts differ, in the order given. `windows` is a list of
  `{starts_after, starts_before}`; the counts are maps keyed by window.
  """
  def windows_to_check(windows, local_counts, d4h_counts) do
    Enum.filter(windows, &(Map.get(local_counts, &1, 0) != Map.get(d4h_counts, &1, 0)))
  end

  @doc "A window per year, `[Jan 1, next Jan 1)`, in UTC."
  def year_windows(first_year, last_year) do
    for year <- first_year..last_year//1, do: {start_of(year, 1), start_of(year + 1, 1)}
  end

  @doc "A window per month of the year that `year_window` starts."
  def month_windows({%DateTime{year: year}, _starts_before}) do
    for month <- 1..12 do
      {next_year, next_month} = if month == 12, do: {year + 1, 1}, else: {year, month + 1}
      {start_of(year, month), start_of(next_year, next_month)}
    end
  end

  defp start_of(year, month),
    do: year |> Date.new!(month, 1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

  # A missing or rejected key needs a person, so it comes back as `{:error, reason}`, as
  # in the full refresh, which reports it on the dashboards.
  @doc """
  Fetches and saves what changed. `{:ok, team, changed}`, where `changed` lists the D4H
  lists that moved, empty when nothing did.
  """
  def call(team, now \\ DateTime.utc_now())

  def call(%Team{d4h_access_key: key}, _now) when key in [nil, ""], do: {:error, :no_key}

  def call(%Team{} = team, now) do
    d4h = D4H.build_context_from_team(team)
    heads = fetch_heads(d4h)

    changed =
      case plan(previous_heads(team), heads) do
        plan when is_map(plan) ->
          apply_plan(d4h, team, plan, heads, now)
          plan.changed

        _seed_or_unchanged ->
          []
      end

    {:ok, save_heads(team, heads, now), changed}
  rescue
    error in D4H.Error ->
      if error.status in [401, 403],
        do: {:error, {:key_rejected, error.status}},
        else: reraise(error, __STACKTRACE__)
  end

  @doc "Every list's head, 4 requests at a time."
  def fetch_heads(d4h) do
    @lists
    |> parallel(&{&1, D4H.fetch_list_head(d4h, "/" <> &1)})
    |> Map.new()
  end

  @doc """
  Records the heads as what this team's copy now matches, and clears any failure. The
  full refresh calls this too, with the heads it saw before it started.
  """
  def save_heads(team, heads, now) do
    encoded =
      Map.new(heads, fn {list, head} ->
        {list,
         %{
           "total_size" => head.total_size,
           "newest_updated_at" =>
             head.newest_updated_at && DateTime.to_iso8601(head.newest_updated_at)
         }}
      end)

    {:ok, team} = Team.update(team, %{d4h_synced_at: now, d4h_sync_state: %{"heads" => encoded}})
    team
  end

  @doc "The heads the last sync or refresh saw, or nil."
  def previous_heads(%Team{d4h_sync_state: %{"heads" => heads}}) when is_map(heads) do
    Map.new(heads, fn {list, head} ->
      {list,
       %{
         total_size: head["total_size"],
         newest_updated_at: head["newest_updated_at"] && parse(head["newest_updated_at"])
       }}
    end)
  end

  def previous_heads(%Team{}), do: nil

  defp parse(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    at
  end

  @doc """
  Notes that D4H rejected the team key, which stops the syncs until a new key is saved
  (`forget_key_rejected/1`) or a refresh gets far enough to save its heads.
  """
  def record_key_rejected(%Team{} = team) do
    state = Map.put(team.d4h_sync_state || %{}, "key_rejected", true)
    {:ok, team} = Team.update(team, %{d4h_sync_state: state})
    team
  end

  def key_rejected?(%Team{d4h_sync_state: %{"key_rejected" => true}}), do: true
  def key_rejected?(%Team{}), do: false

  @doc "The sync state without the rejected key mark, for when a new key is saved."
  def forget_key_rejected(state), do: Map.delete(state || %{}, "key_rejected")

  @doc """
  Notes a failed sync. Returns the team and whether to tell Honeybadger: only once, after
  an hour of failures, since the next sync is 10 minutes away and usually works.
  """
  def record_failure(%Team{} = team, now) do
    state = team.d4h_sync_state || %{}
    failing_since = (state["failing_since"] && parse(state["failing_since"])) || now
    report? = state["reported"] != true and DateTime.diff(now, failing_since) >= 3600

    state =
      Map.merge(state, %{
        "failing_since" => DateTime.to_iso8601(failing_since),
        "reported" => state["reported"] == true or report?
      })

    {:ok, team} = Team.update(team, %{d4h_sync_state: state})
    {team, report?}
  end

  defp apply_plan(d4h, team, plan, heads, now) do
    progress = Progress.quiet(team.id)
    Enum.each(plan.lists, &fetch_list(&1, d4h, team, progress))

    touched =
      d4h
      |> sync_activities(team, plan.activities, now)
      |> MapSet.union(sync_attendance(d4h, team, plan.attendance_since))

    sync_touched_attendance(d4h, team, touched)

    if plan.attendance_since,
      do: check_attendance_counts(d4h, team, heads["attendance"].total_size, now)

    Logger.info("Synced #{Enum.join(plan.changed, ", ")} for team #{team.id}")
  end

  # New members' photos are checked here; the nightly refresh rechecks everyone's.
  defp fetch_list("members", d4h, team, progress) do
    UpsertMembers.call(d4h, team, progress)
    CheckMemberPhotos.call(d4h, team, :unchecked)
  end

  defp fetch_list("member-qualifications", d4h, team, progress),
    do: UpsertQualifications.call(d4h, team, progress)

  defp fetch_list("member-qualification-awards", d4h, team, progress),
    do: UpsertQualificationAwards.call(d4h, team, progress)

  defp fetch_list("member-groups", d4h, team, progress),
    do: UpsertGroups.call(d4h, team, progress)

  defp fetch_list("member-group-memberships", d4h, team, progress),
    do: UpsertGroupMemberships.call(d4h, team, progress)

  # D4H ids of the activities saved or marked deleted whose attendance is worth checking.
  defp sync_activities(_d4h, _team, activities, _now) when activities == %{}, do: MapSet.new()

  defp sync_activities(d4h, team, activities, now) do
    tag_index = d4h |> D4H.fetch_tags() |> Map.new(&{&1.d4h_tag_id, &1.title})

    Enum.reduce(activities, MapSet.new(), fn {kind, cursors}, touched ->
      d4h
      |> sync_activity_kind(team, tag_index, kind, cursors, now)
      |> Enum.into(touched)
    end)
  end

  defp sync_activity_kind(d4h, team, tag_index, kind, cursors, now) do
    listed =
      D4H.reduce_activities_updated_after(d4h, tag_index, kind, cursors.updated_after, [], fn
        rows, acc ->
          Enum.each(rows, &UpsertActivities.upsert(team.id, &1))
          acc ++ Enum.map(rows, & &1.d4h_activity_id)
      end)

    UpsertActivities.clear_deleted(team, listed)
    deleted = if cursors.compare_ids?, do: mark_deleted(d4h, team, kind, now), else: []
    if cursors.touch?, do: listed ++ deleted, else: deleted
  end

  # D4H leaves deleted activities out of its lists, so compare every id it lists with
  # this copy, as the full refresh does. One or two pages per kind. Returns the D4H ids
  # newly marked deleted, so their attendance is checked too.
  defp mark_deleted(d4h, team, kind, now) do
    listed_ids = d4h |> D4H.fetch_activity_ids(kind) |> MapSet.new()
    plan = UpsertActivities.mark_deleted(team, Map.fetch!(@activity_kind, kind), listed_ids, now)

    Activity
    |> where([a], a.team_id == ^team.id and a.id in ^plan.delete)
    |> select([a], a.d4h_activity_id)
    |> Repo.all()
  end

  defp sync_attendance(_d4h, _team, nil), do: MapSet.new()

  defp sync_attendance(d4h, team, since) do
    rows = D4H.fetch_attendances_changed_since(d4h, since)
    context = UpsertAttendances.build_context(team.id)
    Enum.each(rows, &UpsertAttendances.upsert(context, &1))
    MapSet.new(rows, & &1.d4h_activity_id)
  end

  # A deleted attendance row leaves no trace in D4H, so fetch each touched activity's
  # rows whole and drop the local ones D4H didn't return.
  defp sync_touched_attendance(d4h, team, touched) do
    touched = MapSet.to_list(touched)

    activities =
      Activity
      |> where([a], a.team_id == ^team.id and a.d4h_activity_id in ^touched)
      |> select([a], {a.id, a.d4h_activity_id})
      |> Repo.all()

    fetched = parallel(activities, &fetch_activity_attendance(d4h, &1))
    context = UpsertAttendances.build_context(team.id)

    for {activity_id, rows} <- fetched do
      Enum.each(rows, &UpsertAttendances.upsert(context, &1))
      synced = MapSet.new(rows, & &1.d4h_attendance_id)
      UpsertAttendances.delete_stale_for_activity(team.id, activity_id, synced)
    end
  end

  defp fetch_activity_attendance(d4h, {id, d4h_id}) do
    case D4H.fetch_attendance_infos(d4h, d4h_id) do
      {:ok, rows} -> {id, rows}
      {:error, error} -> raise error
    end
  end

  # Finds deletes on activities nothing else touched. Off by rows D4H has but this copy
  # skips (an unknown member or activity), the counts never match, so this refetches at
  # most one month per sync and logs it.
  defp check_attendance_counts(d4h, team, d4h_total, now) do
    local_total = team.id |> team_attendances() |> Repo.aggregate(:count)

    if local_total != d4h_total do
      years = year_windows(first_year(team.id, now), now.year + 1)

      with [year | _] <- differing_windows(d4h, team, years),
           [month | _] <- differing_windows(d4h, team, month_windows(year)) do
        refetch_window(d4h, team, month)
      else
        [] ->
          Logger.info(
            "Attendance counts differ for team #{team.id} (#{local_total} here, " <>
              "#{d4h_total} in D4H), but no year or month does"
          )
      end
    end
  end

  defp differing_windows(d4h, team, windows) do
    local = Map.new(windows, &{&1, local_count(team.id, &1)})

    d4h_counts =
      windows
      |> parallel(fn {from, to} = window ->
        {window, D4H.fetch_attendance_count(d4h, from, to)}
      end)
      |> Map.new()

    windows_to_check(windows, local, d4h_counts)
  end

  defp refetch_window(d4h, team, {from, to}) do
    context = UpsertAttendances.build_context(team.id)

    synced =
      D4H.reduce_attendances_between(d4h, from, to, MapSet.new(), fn rows, acc ->
        Enum.each(rows, &UpsertAttendances.upsert(context, &1))
        Enum.into(rows, acc, & &1.d4h_attendance_id)
      end)

    deleted = UpsertAttendances.delete_stale_between(team.id, from, to, synced)

    Logger.info(
      "Refetched attendance for team #{team.id} from #{Date.to_iso8601(from)}: " <>
        "#{MapSet.size(synced)} rows, #{deleted} deleted"
    )
  end

  defp first_year(team_id, now) do
    case team_id |> team_attendances() |> select([a], min(a.started_at)) |> Repo.one() do
      %DateTime{year: year} -> year
      nil -> now.year
    end
  end

  defp local_count(team_id, {from, to}) do
    team_id
    |> team_attendances()
    |> where([a], a.started_at >= ^from and a.started_at < ^to)
    |> Repo.aggregate(:count)
  end

  defp team_attendances(team_id) do
    team_member_ids = from(m in Member, where: m.team_id == ^team_id, select: m.id)
    where(Attendance, [a], a.member_id in subquery(team_member_ids))
  end

  # Runs `fun` 4 at a time and returns the results in order. An error in one comes back
  # here as itself, so the D4H.Error rescue in call/2 still sees it.
  defp parallel(enum, fun) do
    enum
    |> Task.async_stream(
      fn item ->
        try do
          {:ok, fun.(item)}
        rescue
          error -> {:error, error, __STACKTRACE__}
        end
      end,
      max_concurrency: @concurrency,
      timeout: :timer.minutes(2)
    )
    |> Enum.map(fn
      {:ok, {:ok, result}} -> result
      {:ok, {:error, error, stacktrace}} -> reraise error, stacktrace
    end)
  end
end
