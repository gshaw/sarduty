defmodule App.Operation.ChangeAttendance do
  @moduledoc """
  Changes the attendance of the members a team admin checks on an activity's Members tab
  (#766), from the start until it's published: one change set per press, of source
  `:change_attendance`, applied at once. SAR Duty emails nobody.

  - `:attended` marks the member's row (`Attendance.one_per_member/1`) attending with the
    activity's start and finish, as a reply does, and clears a no-show.
  - `:absent` marks every row the member has absent, with no hours.
  - `:remove` deletes every row they have, as RemoveMembers does.

  Attended passes over a member shown attended, and Absent one shown absent: changes?/2
  says which change a member, and the tab's button counts them. The tab sends the status
  it showed for each member, and a member whose row changed since is left out.

  plan/3 decides who changes, pure; call/6 reads and writes.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.NoShow
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.RemoveMembers
  alias App.Repo
  alias Service.Format

  @changes [:attended, :absent, :remove]

  @doc "The changes the tab offers."
  def changes, do: @changes

  @doc """
  Whether `change` changes a member the tab shows with D4H `status`: Attended passes over
  the attended, Absent the absent, and Remove takes everyone. Pure.
  """
  def changes?(:attended, status), do: status != "attending"
  def changes?(:absent, status), do: status != "absent"
  def changes?(:remove, _status), do: true

  @doc """
  Who changes, from `checked`, each `{%Member{}, status}` with the D4H status the tab
  showed for them, and `rows`, the copy's rows on the activity in any status.

  `%{change: [%{member:, rows:}], not_changed: [{member, reason}]}`, where `rows` are the
  rows the change writes. A member changes?/2 passes over is in neither list. One is left
  out as `:changed` when their row (`Attendance.one_per_member/1`) no longer has the
  status shown, and as `:gone` with no row at all. Pure.
  """
  def plan(change, checked, rows) when change in @changes do
    by_member = Enum.group_by(rows, & &1.member_id)

    {change_list, not_changed} =
      checked
      |> changed_by(change)
      |> Enum.map(fn {member, shown} ->
        plan_member(change, member, shown, by_member[member.id])
      end)
      |> Enum.split_with(&is_map/1)

    %{change: change_list, not_changed: not_changed}
  end

  # Each member once, leaving out those the change passes over.
  defp changed_by(checked, change) do
    checked
    |> Enum.uniq_by(fn {member, _status} -> member.id end)
    |> Enum.filter(fn {_member, shown} -> changes?(change, shown) end)
  end

  defp plan_member(_change, member, _shown, nil), do: {member, :gone}

  defp plan_member(change, member, shown, rows) do
    [row] = Attendance.one_per_member(rows)

    if row.status == shown,
      do: %{member: member, rows: writes(change, row, rows)},
      else: {member, :changed}
  end

  defp writes(:attended, row, _rows), do: [row]
  defp writes(:absent, _row, rows), do: Enum.reject(rows, &(&1.status == "absent"))
  defp writes(:remove, _row, rows), do: rows

  @doc """
  The change set rows for plan/3's `change`. Each keeps the status of its own row in the
  copy, so the applier skips one D4H has changed since.
  """
  def rows(change, %Activity{} = activity, entries) do
    for %{member: member, rows: rows} <- entries, row <- rows do
      row_for(change, activity, member, row)
    end
  end

  defp row_for(:attended, activity, member, row) do
    %ChangeSetRow{
      action: :update_attendance,
      member_id: member.id,
      d4h_record_id: row.d4h_attendance_id,
      old_value: %{
        "status" => row.status,
        "starts_at" => ApplyChangeSet.iso(row.started_at),
        "ends_at" => ApplyChangeSet.iso(row.finished_at)
      },
      new_value: %{
        "status" => "ATTENDING",
        "starts_at" => ApplyChangeSet.iso(activity.started_at),
        "ends_at" => ApplyChangeSet.iso(activity.finished_at)
      }
    }
  end

  defp row_for(:absent, _activity, member, row) do
    %ChangeSetRow{
      action: :update_attendance,
      member_id: member.id,
      d4h_record_id: row.d4h_attendance_id,
      old_value: %{"status" => row.status},
      new_value: %{"status" => "ABSENT"}
    }
  end

  defp row_for(:remove, _activity, member, row) do
    %ChangeSetRow{
      action: :delete_attendance,
      member_id: member.id,
      d4h_record_id: row.d4h_attendance_id,
      old_value: %{"d4h_member_id" => member.d4h_member_id, "status" => row.status},
      new_value: %{}
    }
  end

  @doc """
  Whether a team admin can change the activity's attendance by hand at `now`: from the
  start, on one neither deleted nor published. Read from the copy, so call/6 checks again
  and D4H refuses a published one. Pure.
  """
  def open?(%Activity{} = activity, %DateTime{} = now),
    do:
      not Activity.deleted?(activity) and Activity.started?(activity, now) and
        not Activity.locked?(activity)

  @doc """
  Makes `change` for the checked members, each `{member_id, status}` with the status the
  tab showed, from `user`. `{:ok, %{change:, changed: members, not_changed: [{member,
  reason}]}}`, where the reason is `:changed`, `:gone`, or D4H's refusal. `{:error,
  reason}` for nobody it changes (`:none_selected`), an activity that is deleted
  (`:deleted`), has not started (`:not_started`), or is published (`:published`), or when
  D4H refuses; error_text/2 words it.
  """
  def call(
        %Team{} = team,
        %Activity{team_id: team_id} = activity,
        checked,
        change,
        %User{} = user,
        now
      )
      when team_id == team.id and change in @changes do
    checked = RemoveMembers.scope(team, checked)

    cond do
      activity.deleted_at ->
        {:error, :deleted}

      not Activity.started?(activity, now) ->
        {:error, :not_started}

      activity.is_published ->
        {:error, :published}

      not Enum.any?(checked, fn {_member, shown} -> changes?(change, shown) end) ->
        {:error, :none_selected}

      true ->
        run(team, activity, change, checked, user, now)
    end
  end

  defp run(team, activity, change, checked, user, now) do
    plan = plan(change, checked, RemoveMembers.copy_rows(activity))

    with {:ok, rows} <- apply_plan(team, activity, change, plan, user, now) do
      {:ok, finish(activity, change, plan, rows)}
    end
  end

  defp apply_plan(_team, _activity, _change, %{change: []}, _user, _now), do: {:ok, []}

  defp apply_plan(team, activity, change, plan, user, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :change_attendance,
          activity_id: activity.id,
          proposed_by_user_id: user.id
        },
        rows(change, activity, plan.change)
      )

    ApplyChangeSet.call(team, change_set, user, now)
  end

  # A member changes once every row of theirs went through.
  defp finish(activity, change, plan, rows) do
    by_id = Map.new(rows, &{&1.d4h_record_id, &1})

    {changed, kept} =
      Enum.split_with(plan.change, fn entry ->
        Enum.all?(entry.rows, &(by_id[&1.d4h_attendance_id].status == :applied))
      end)

    write_copy(activity, change, rows, changed)

    %{
      change: change,
      changed: Enum.map(changed, & &1.member),
      not_changed: plan.not_changed ++ Enum.map(kept, &RemoveMembers.kept_reason(&1, by_id))
    }
  end

  # The copy takes what D4H was sent, so the tab, the counts, and Travel's badge follow
  # at once and the next refresh sees nothing new.
  defp write_copy(activity, change, rows, changed) do
    applied = for %ChangeSetRow{status: :applied} = row <- rows, do: row.d4h_record_id

    query =
      where(Attendance, [a], a.activity_id == ^activity.id and a.d4h_attendance_id in ^applied)

    Repo.transaction(fn -> write_rows(query, activity, change, changed) end)
  end

  defp write_rows(query, _activity, :remove, _changed), do: Repo.delete_all(query)

  defp write_rows(query, _activity, :absent, _changed),
    do: Repo.update_all(query, set: [status: "absent"])

  defp write_rows(query, activity, :attended, changed) do
    Repo.update_all(query,
      set: [
        status: "attending",
        started_at: activity.started_at,
        finished_at: activity.finished_at,
        duration_in_minutes:
          Service.Convert.duration_to_minutes(activity.started_at, activity.finished_at)
      ]
    )

    for %{member: member} <- changed, do: NoShow.clear(activity.id, member.id)
  end

  @doc """
  What call/6 did, as one line: "3 members marked absent.", then each member not changed,
  with why.
  """
  def result_text(%{change: change, changed: changed, not_changed: not_changed}) do
    [changed_text(change, length(changed)) | not_changed_text(not_changed)]
    |> Enum.join(" ")
  end

  defp changed_text(_change, 0), do: "Nobody was changed."

  defp changed_text(:attended, n),
    do: Format.count(n, one: "1 member marked attended.", many: "%d members marked attended.")

  defp changed_text(:absent, n),
    do: Format.count(n, one: "1 member marked absent.", many: "%d members marked absent.")

  defp changed_text(:remove, n),
    do: Format.count(n, one: "1 member removed.", many: "%d members removed.")

  defp not_changed_text(not_changed) do
    not_changed
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.sort_by(fn {_reason, members} -> String.downcase(hd(members).name) end)
    |> Enum.map(fn {reason, members} -> not_changed_line(reason, members) end)
  end

  defp not_changed_line(:gone, members),
    do: "#{names(members)} #{were(members)} off the activity already."

  defp not_changed_line(:changed, members),
    do:
      "#{names(members)} #{were(members)} not changed: their attendance changed since the page loaded. Check it and try again."

  defp not_changed_line(error, members),
    do: "#{names(members)} #{were(members)} not changed: #{error}"

  defp were([_one]), do: "was"
  defp were(_many), do: "were"

  defp names(members), do: members |> Enum.map(& &1.name) |> Format.and_list()

  @doc "What to show for call/6's `{:error, reason}`."
  def error_text(_team, :none_selected), do: "Check the members to change first."
  def error_text(_team, :no_team_key), do: "Save your team's access key in team settings first."
  def error_text(_team, :deleted), do: "This activity is deleted."
  def error_text(_team, :not_started), do: "Nobody was changed. The activity has not started."

  def error_text(team, :published),
    do:
      "Nobody was changed. Attendance cannot be changed once the activity is published. #{D4H.unpublish_text(team)}"

  def error_text(team, error), do: "Nobody was changed. #{D4H.error_text(team, error)}"
end
