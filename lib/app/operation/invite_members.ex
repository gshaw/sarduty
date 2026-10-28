defmodule App.Operation.InviteMembers do
  @moduledoc """
  Adds members to an activity as No reply (#564), by name or by group: each gets an
  attendance row in D4H as "REQUESTED", for the activity's times, and answers it
  themselves. SAR Duty emails nobody. A change set applied at once, of source `:invite`
  from the Add members page or `:template` for a template's groups (#162).

  Only before the start, and never on a published activity. A group leaves out its
  members away on the activity's day; a name never does. The copy gets each row D4H
  took, so the activity's page and its email button show them at once.

  plan/3 decides who goes, pure; call/6 reads and writes.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  @doc """
  Who goes, from `picks`, each `{reason, %Member{}}` where the reason is `:name` or the
  `%Group{}` they came from. `known` is `%{on_activity: member_ids, away: member_ids,
  now: now}`: who has a row on the activity in any status, and who is away on its day.

  `%{add: picks, on_activity: members, away: members}`. A member picked twice goes once,
  with the first reason. Anyone on the activity is left out, since D4H would add a
  second row, and so is anyone away who only came from a group. Retired members and
  members marked not a person are left out and not named; retiring members never reach
  the picks (Member.counted_query/1). Both lists go A to Z.
  """
  def plan(%Activity{}, picks, %{on_activity: on_activity, away: away, now: now}) do
    on_activity = MapSet.new(on_activity)
    away = MapSet.new(away)

    {left_on, picks} =
      picks
      |> Enum.filter(&addable?(&1, now))
      |> Enum.split_with(&MapSet.member?(on_activity, member_id(&1)))

    {left_away, picks} = Enum.split_with(picks, &away_from_group?(&1, away))
    add = Enum.uniq_by(picks, &member_id/1)

    %{add: add, on_activity: names(left_on, []), away: names(left_away, add)}
  end

  defp addable?({_reason, member}, now),
    do: Member.current?(member, now) and not member.not_a_person

  defp away_from_group?({reason, member}, away),
    do: reason != :name and MapSet.member?(away, member.id)

  defp member_id({_reason, member}), do: member.id

  # The members left out, by name, leaving out any `add` has from another pick.
  defp names(left, add) do
    added = MapSet.new(add, &member_id/1)

    left
    |> Enum.reject(&MapSet.member?(added, member_id(&1)))
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  @doc "The rows that add `add`, plan/3's picks, to the activity."
  def rows(%Activity{} = activity, add) do
    for {reason, member} <- add do
      %ChangeSetRow{
        action: :create_attendance,
        member_id: member.id,
        reason: reason_text(reason),
        new_value: %{
          "d4h_activity_id" => activity.d4h_activity_id,
          "d4h_member_id" => member.d4h_member_id,
          "status" => "REQUESTED",
          "starts_at" => ApplyChangeSet.iso(activity.started_at),
          "ends_at" => ApplyChangeSet.iso(activity.finished_at)
        }
      }
    end
  end

  @doc ~s(Why a member is in the list: "Added by name" or "In the Boat Operators group".)
  def reason_text(:name), do: "Added by name"
  def reason_text(%Group{title: title}), do: "In the #{title} group"

  @doc """
  Adds the picks from `user`. `{:ok, %{rows: rows, on_activity: members, away:
  members}}`, with each row as D4H answered, or none when plan/3 left everyone out.
  `{:error, reason}` for an activity that is deleted (`:deleted`), has started
  (`:started`), or is published (`:published`), or when D4H refuses; error_text/2 words
  it.
  """
  def call(
        %Team{} = team,
        %Activity{team_id: team_id} = activity,
        picks,
        %User{} = user,
        source,
        now
      )
      when team_id == team.id and source in [:invite, :template] do
    cond do
      activity.deleted_at -> {:error, :deleted}
      not DateTime.before?(now, activity.started_at) -> {:error, :started}
      activity.is_published -> {:error, :published}
      true -> add(team, activity, scope(team, picks), user, source, now)
    end
  end

  defp add(team, activity, picks, user, source, now) do
    known = %{on_activity: on_activity(activity), away: away(team, activity), now: now}
    plan = plan(activity, picks, known)

    case plan.add do
      [] ->
        {:ok, %{plan_result(plan) | rows: []}}

      add ->
        with {:ok, rows} <- apply_rows(team, activity, rows(activity, add), user, source, now) do
          write_copy(activity, rows)
          {:ok, %{plan_result(plan) | rows: rows}}
        end
    end
  end

  defp plan_result(plan), do: %{rows: [], on_activity: plan.on_activity, away: plan.away}

  # Each pick again from the team's own members and groups, never a struct from a page.
  defp scope(team, picks) do
    members =
      Member
      |> where([m], m.team_id == ^team.id and m.id in ^Enum.map(picks, &elem(&1, 1).id))
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    for {reason, member} <- picks,
        reason == :name or reason.team_id == team.id,
        fresh = members[member.id],
        do: {reason, fresh}
  end

  @doc """
  The picks a group adds, each `{%Group{}, %Member{}}`: its current members who are
  people, by group and then by name. Groups from another team add nobody.
  """
  def group_picks(%Team{} = team, groups, now) do
    groups = Enum.filter(groups, &(&1.team_id == team.id))
    members = members_by_group(team, Enum.map(groups, & &1.id), now)
    for %Group{} = group <- groups, member <- Map.get(members, group.id, []), do: {group, member}
  end

  defp members_by_group(team, ids, now) do
    Member
    |> join(:inner, [m], gm in GroupMember, on: gm.member_id == m.id)
    |> where([m, gm], m.team_id == ^team.id and gm.group_id in ^ids)
    |> Member.current_query(now)
    |> Member.counted_query()
    |> order_by([m], asc: m.name)
    |> select([m, gm], {gm.group_id, m})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "Ids of the members with a row on the activity, in any status."
  def on_activity(%Activity{} = activity) do
    Attendance
    |> join(:inner, [a], m in assoc(a, :member))
    |> where([a, m], a.activity_id == ^activity.id and m.team_id == ^activity.team_id)
    |> select([a], a.member_id)
    |> Repo.all()
  end

  @doc "Ids of the members away on the activity's day, in the team's time zone."
  def away(%Team{} = team, %Activity{} = activity) do
    team
    |> MemberAwayPeriod.away_query(day(team, activity))
    |> Repo.all()
    |> Enum.map(& &1.member_id)
  end

  defp day(team, activity),
    do: activity.started_at |> DateTime.shift_zone!(team.timezone) |> DateTime.to_date()

  defp apply_rows(team, activity, rows, user, source, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: source,
          activity_id: activity.id,
          proposed_by_user_id: user.id
        },
        rows
      )

    ApplyChangeSet.call(team, change_set, user, now)
  end

  # The copy takes the rows D4H took, as the next refresh would write them, so it sees
  # nothing new.
  defp write_copy(activity, rows) do
    for %ChangeSetRow{status: :applied} = row <- rows do
      Attendance.insert!(%{
        member_id: row.member_id,
        activity_id: activity.id,
        d4h_attendance_id: row.d4h_record_id,
        duration_in_minutes:
          Service.Convert.duration_to_minutes(activity.started_at, activity.finished_at),
        started_at: activity.started_at,
        finished_at: activity.finished_at,
        status: "requested"
      })
    end
  end

  @doc """
  What call/6's rows did, as sentences: "8 members added." or "Nobody was added.", then
  how many D4H had on the activity by then, then each refusal with why.
  """
  def result_lines(rows) do
    {applied, other} = Enum.split_with(rows, &(&1.status == :applied))
    {skipped, failed} = Enum.split_with(other, &(&1.status == :skipped))

    added =
      if applied == [],
        do: "Nobody was added.",
        else: "#{count_members(length(applied))} added."

    not_added =
      failed
      |> Enum.group_by(& &1.error)
      |> Enum.map(fn {error, rows} -> "#{count_members(length(rows))} not added: #{error}" end)

    Enum.reject([added, skipped_text(skipped) | not_added], &is_nil/1)
  end

  # The applier skips a member D4H has on the activity by then. Its own words ask for a
  # review, which fits Send attendance, not this.
  defp skipped_text([]), do: nil

  defp skipped_text(rows) do
    rows
    |> length()
    |> Service.Format.count(
      one: "1 member was on the activity already.",
      many: "%d members were on the activity already."
    )
  end

  defp count_members(n), do: Service.Format.count(n, one: "%d member", many: "%d members")

  @doc "What to show for call/6's `{:error, reason}`."
  def error_text(_team, :no_team_key), do: "Save your team's access key in team settings first."
  def error_text(_team, :deleted), do: "This activity is deleted."
  def error_text(_team, :started), do: "Nobody was added. The activity has started."

  def error_text(team, :published),
    do:
      "Nobody was added. Attendance cannot be changed once the activity is published. #{D4H.unpublish_text(team)}"

  def error_text(team, error), do: "Nobody was added. #{D4H.error_text(team, error)}"
end
