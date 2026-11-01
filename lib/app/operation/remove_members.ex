defmodule App.Operation.RemoveMembers do
  @moduledoc """
  Takes members off an activity (#704), from its Remove members page: every row each
  checked member has, as one change set of `:delete_attendance` rows of source
  `:remove`, applied at once. Only before the start, and never on a published activity.

  No reply and Can't make it members go with no email. A signed up member who has an
  email gets the team admin's message, which is required for them and kept as the rows'
  reason; one with no email gets nothing, and the page says to tell them. A member's
  email goes only once none of their rows is left.

  plan/3 decides who goes, pure; call/6 reads and writes.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.SendActivityUpdate
  alias App.Repo
  alias App.Validate.Message
  alias Service.Format

  @doc """
  Who goes, from `checked`, each `{%Member{}, status}` with the D4H status the page
  showed for them, and `rows`, the copy's rows on the activity in any status.

  `{:ok, %{remove: [%{member:, rows:, email?:}], not_removed: [{member, reason}]}}`. A
  member is left out as `:changed` when their row (`Attendance.one_per_member/1`) no
  longer has the status shown, and as `:gone` with no row at all. Each member goes with
  every row they have: D4H allows two (#520), and one left keeps them on. `email?` is a
  signed up member with an email. `{:error, :no_message}` when one gets an email and
  `message` is nil.
  """
  def plan(checked, rows, message) do
    by_member = Enum.group_by(rows, & &1.member_id)

    {remove, not_removed} =
      checked
      |> Enum.uniq_by(fn {member, _status} -> member.id end)
      |> Enum.map(fn {member, shown} -> plan_member(member, shown, by_member[member.id]) end)
      |> Enum.split_with(&is_map/1)

    if message == nil and Enum.any?(remove, & &1.email?),
      do: {:error, :no_message},
      else: {:ok, %{remove: remove, not_removed: not_removed}}
  end

  defp plan_member(member, _shown, nil), do: {member, :gone}

  defp plan_member(member, shown, rows) do
    [row] = Attendance.one_per_member(rows)

    if row.status == shown,
      do: %{member: member, rows: rows, email?: shown == "attending" and email?(member)},
      else: {member, :changed}
  end

  @doc "Whether SAR Duty can email the member."
  def email?(%Member{email: email}), do: email not in [nil, ""]

  @doc """
  The rows that take plan/3's `remove` off the activity. Each keeps the status of its own
  row in the copy, so the applier skips one D4H has changed since. A member who gets the
  email has it as their rows' reason, for the activity's history.
  """
  def rows(remove, message) do
    for %{member: member, rows: rows, email?: email?} <- remove, row <- rows do
      %ChangeSetRow{
        action: :delete_attendance,
        member_id: member.id,
        d4h_record_id: row.d4h_attendance_id,
        reason: if(email?, do: message),
        old_value: %{"d4h_member_id" => member.d4h_member_id, "status" => row.status},
        new_value: %{}
      }
    end
  end

  @doc """
  Removes the checked members, each `{member_id, status}` with the status the page
  showed, from `user`. `{:ok, %{removed: members, emailed: members, not_removed:
  [{member, reason}]}}`, where the reason is `:changed`, `:gone`, or D4H's refusal.
  `{:error, reason}` for nobody checked (`:none_selected`), a missing or long message
  (`:no_message`, `:message_too_long`), an activity that is deleted (`:deleted`), has
  started (`:started`), or is published (`:published`), or when D4H refuses; error_text/2
  words it.
  """
  def call(
        %Team{} = team,
        %Activity{team_id: team_id} = activity,
        checked,
        message,
        %User{} = user,
        now
      )
      when team_id == team.id do
    message = Message.normalize(message)

    cond do
      activity.deleted_at -> {:error, :deleted}
      Activity.started?(activity, now) -> {:error, :started}
      activity.is_published -> {:error, :published}
      checked == [] -> {:error, :none_selected}
      not Message.fits?(message) -> {:error, :message_too_long}
      true -> remove(team, activity, scope(team, checked), message, user, now)
    end
  end

  defp remove(team, activity, checked, message, user, now) do
    with {:ok, plan} <- plan(checked, copy_rows(activity), message),
         {:ok, rows} <- apply_plan(team, activity, plan, message, user, now) do
      {:ok, finish(activity, plan, rows, user, message, now)}
    end
  end

  # Each member again from the team's own, never a struct from a page.
  defp scope(team, checked) do
    members =
      Member
      |> where([m], m.team_id == ^team.id and m.id in ^Enum.map(checked, &elem(&1, 0)))
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    for {id, status} <- checked, member = members[id], do: {member, status}
  end

  defp copy_rows(activity) do
    Attendance
    |> join(:inner, [a], m in assoc(a, :member))
    |> where([a, m], a.activity_id == ^activity.id and m.team_id == ^activity.team_id)
    |> Repo.all()
  end

  defp apply_plan(_team, _activity, %{remove: []}, _message, _user, _now), do: {:ok, []}

  defp apply_plan(team, activity, plan, message, user, now) do
    change_set =
      ChangeSet.propose!(
        %ChangeSet{
          team_id: team.id,
          source: :remove,
          activity_id: activity.id,
          proposed_by_user_id: user.id
        },
        rows(plan.remove, message)
      )

    ApplyChangeSet.call(team, change_set, user, now)
  end

  # A member with a row left stays on, and gets nothing.
  defp finish(activity, plan, rows, user, message, now) do
    by_id = Map.new(rows, &{&1.d4h_record_id, &1})

    {removed, kept} =
      Enum.split_with(plan.remove, fn entry ->
        Enum.all?(entry.rows, &(by_id[&1.d4h_attendance_id].status == :applied))
      end)

    emailed = for %{email?: true, member: member} <- removed, do: member
    write(activity, rows, emailed, user, message, now)

    %{
      removed: Enum.map(removed, & &1.member),
      emailed: emailed,
      not_removed: plan.not_removed ++ Enum.map(kept, &kept_reason(&1, by_id))
    }
  end

  # The copy loses the rows D4H deleted, and each member with none left gets their
  # email, in one transaction.
  defp write(activity, rows, emailed, user, message, now) do
    applied = for %ChangeSetRow{status: :applied} = row <- rows, do: row.d4h_record_id

    Repo.transaction(fn ->
      Attendance
      |> where([a], a.activity_id == ^activity.id and a.d4h_attendance_id in ^applied)
      |> Repo.delete_all()

      for member <- emailed,
          do: SendActivityUpdate.queue(activity, member, user, message, now, :removal)
    end)
  end

  # The applier skips a row D4H changed since the copy, and that is the member's reply.
  defp kept_reason(entry, by_id) do
    row =
      entry.rows
      |> Enum.map(&by_id[&1.d4h_attendance_id])
      |> Enum.find(&(&1.status != :applied))

    {entry.member, if(row.status == :skipped, do: :changed, else: row.error)}
  end

  @doc """
  What call/6 did, as one line: "4 members removed. Drew Patel gets your email.", then
  each member not removed, with why.
  """
  def result_text(%{removed: removed, emailed: emailed, not_removed: not_removed}) do
    [removed_text(removed), emailed_text(emailed) | not_removed_text(not_removed)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp removed_text([]), do: "Nobody was removed."

  defp removed_text(removed),
    do: removed |> length() |> Format.count(one: "1 member removed.", many: "%d members removed.")

  defp emailed_text([]), do: nil
  defp emailed_text([member]), do: "#{member.name} gets your email."
  defp emailed_text(members), do: "#{names(members)} get your email."

  defp not_removed_text(not_removed) do
    not_removed
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.sort_by(fn {_reason, members} -> String.downcase(hd(members).name) end)
    |> Enum.map(fn {reason, members} -> not_removed_line(reason, members) end)
  end

  defp not_removed_line(:gone, members),
    do: "#{names(members)} #{were(members)} off the activity already."

  defp not_removed_line(:changed, members),
    do:
      "#{names(members)} #{were(members)} not removed: their reply changed since you opened the page. Review again."

  defp not_removed_line(error, members),
    do: "#{names(members)} #{were(members)} not removed: #{error}"

  defp were([_one]), do: "was"
  defp were(_many), do: "were"

  defp names(members), do: members |> Enum.map(& &1.name) |> Format.and_list()

  @doc "What to show for call/6's `{:error, reason}`."
  def error_text(_team, :none_selected), do: "Select at least 1 member to remove."
  def error_text(_team, :no_message), do: "Enter a message for the signed up members."
  def error_text(_team, :message_too_long), do: Message.error_text()
  def error_text(_team, :no_team_key), do: "Save your team's access key in team settings first."
  def error_text(_team, :deleted), do: "This activity is deleted."
  def error_text(_team, :started), do: "Nobody was removed. The activity has started."

  def error_text(team, :published),
    do:
      "Nobody was removed. Attendance cannot be changed once the activity is published. #{D4H.unpublish_text(team)}"

  def error_text(team, error), do: "Nobody was removed. #{D4H.error_text(team, error)}"
end
