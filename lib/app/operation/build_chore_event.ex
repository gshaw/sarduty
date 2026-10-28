defmodule App.Operation.BuildChoreEvent do
  @moduledoc """
  Plans one chore event's send (#341): the change set rows that make the D4H event match
  its accepted chores. SAR Duty owns the event, so each send rebuilds it; there are no
  added, changed, or skipped cases, and edits made in D4H are replaced.

  - The event is titled for its chore category and month. It starts and ends at 00:00 on
    the 1st of its month in the team's time zone, so it stays put as chores come in: zero
    length, since members' hours are on their attendance. It counts in that month's year.
  - Each member with accepted chores has one attendance, from the event's start, for
    their total. Anyone else's attendance on it is deleted.
  - An event gets its tags in their own row, so a refusal shows: a new one just after it
    is made, and a sent one only when it lacks its hours tag, once it is back to a draft
    (D4H refuses tags on a published activity). It is published last, once its
    attendance is in, since D4H locks a published activity's attendance; a published one
    goes back to a draft first.

  Pure: `plan/4` takes values and returns rows. App.Operation.SendChores reads D4H.
  """

  alias App.Model.ChangeSetRow
  alias Service.ChoreEventText

  @kind "event"

  @doc """
  The rows for one event. `state` is nil when D4H has no event yet, or
  `%{d4h_activity_id:, published?:}`. `chores` are the accepted chores, with members.
  `current` is D4H's attendance on the event now (`D4H.AttendanceInfo`), read for ids.
  `event` is `%{category:, month:, timezone:, tags:}`, with the chore category's title,
  the first day of the event's month, and the tags to set (`d4h_tag_id` and `title`), or
  `[]` to leave them.
  """
  def plan(state, chores, current, event)

  # Nothing accepted and nothing in D4H: nothing to send.
  def plan(nil, [], _current, _event), do: []

  def plan(nil, chores, _current, event) do
    starts_at = starts_at(event.month, event.timezone)
    totals = member_totals(chores)

    create = %ChangeSetRow{
      action: :create_activity,
      new_value:
        chores
        |> activity_fields(event, starts_at)
        |> Map.merge(%{"kind" => @kind, "full_team" => false, "shared" => false})
    }

    attendance =
      for {member, minutes} <- totals,
          do: create_attendance(member, minutes, starts_at, %{"created_in_set" => true})

    publish = %ChangeSetRow{
      action: :publish_activity,
      old_value: %{"kind" => @kind},
      new_value: %{"created_in_set" => true, "published" => true}
    }

    Enum.concat([[create], tags_rows(event.tags, nil), attendance, [publish]])
  end

  # Every chore declined or moved off: the event keeps its title and times, loses its
  # attendance, and stays a draft.
  def plan(%{d4h_activity_id: id} = state, [], current, _event) do
    unpublish = if state.published?, do: [publish_row(id, false)], else: []

    update = %ChangeSetRow{
      action: :update_activity,
      d4h_record_id: id,
      old_value: %{"kind" => @kind},
      new_value: %{"description" => ChoreEventText.description([])}
    }

    unpublish ++ [update] ++ delete_rows([], current)
  end

  def plan(%{d4h_activity_id: id} = state, chores, current, event) do
    starts_at = starts_at(event.month, event.timezone)
    totals = member_totals(chores)

    update = %ChangeSetRow{
      action: :update_activity,
      d4h_record_id: id,
      old_value: %{"kind" => @kind},
      new_value: activity_fields(chores, event, starts_at)
    }

    unpublish = if state.published?, do: [publish_row(id, false)], else: []

    Enum.concat([
      unpublish,
      [update],
      tags_rows(event.tags, id),
      attendance_rows(id, totals, current, starts_at),
      delete_rows(totals, current),
      [publish_row(id, true)]
    ])
  end

  # Tags for the event `id`, or for the one the set makes when `id` is nil.
  defp tags_rows([], _id), do: []

  defp tags_rows(tags, id) do
    new_value = %{
      "tag_ids" => Enum.map(tags, & &1.d4h_tag_id),
      "titles" => Enum.map(tags, & &1.title)
    }

    [
      %ChangeSetRow{
        action: :set_activity_tags,
        d4h_record_id: id,
        old_value: %{"kind" => @kind},
        new_value: if(id, do: new_value, else: Map.put(new_value, "created_in_set", true))
      }
    ]
  end

  # Each member's attendance: a new row, a changed one, or none when it is right.
  defp attendance_rows(id, totals, current, starts_at) do
    by_member = current |> Enum.uniq_by(& &1.d4h_member_id) |> Map.new(&{&1.d4h_member_id, &1})

    Enum.flat_map(totals, fn {member, minutes} ->
      case by_member[member.d4h_member_id] do
        nil -> [create_attendance(member, minutes, starts_at, %{"d4h_activity_id" => id})]
        info -> update_attendance(info, member, minutes, starts_at)
      end
    end)
  end

  # Anyone on the event without accepted chores, whoever added them, and any second row
  # for a member: D4H lets a member attend one activity twice.
  defp delete_rows(totals, current) do
    members = MapSet.new(totals, fn {member, _minutes} -> member.d4h_member_id end)

    keep =
      current
      |> Enum.filter(&MapSet.member?(members, &1.d4h_member_id))
      |> Enum.uniq_by(& &1.d4h_member_id)

    for info <- current, info not in keep do
      %ChangeSetRow{
        action: :delete_attendance,
        d4h_record_id: info.d4h_attendance_id,
        old_value: %{"d4h_member_id" => info.d4h_member_id, "status" => info.status},
        new_value: %{}
      }
    end
  end

  @doc "When the event starts: 00:00 on the 1st of its month, in the team's time zone."
  def starts_at(%Date{} = month, timezone) do
    month
    |> Date.beginning_of_month()
    |> Service.Convert.local_to_utc(~T[00:00:00], timezone)
  end

  @doc "Each member's total accepted minutes, by name: `[{member, minutes}]`."
  def member_totals(chores) do
    chores
    |> Enum.group_by(& &1.member)
    |> Enum.map(fn {member, chores} ->
      {member, chores |> Enum.map(& &1.minutes) |> Enum.sum()}
    end)
    |> Enum.sort_by(fn {member, _minutes} -> {String.downcase(member.name), member.id} end)
  end

  defp activity_fields(chores, event, starts_at) do
    %{
      "title" => ChoreEventText.title(event.category, event.month),
      "started_at" => iso(starts_at),
      "description" => ChoreEventText.description(chores),
      "finished_at" => iso(starts_at),
      # None, but sent: D4H won't publish one whose tracking number is null.
      "tracking_number" => ""
    }
  end

  defp create_attendance(member, minutes, starts_at, extra) do
    %ChangeSetRow{
      action: :create_attendance,
      member_id: member.id,
      new_value:
        Map.merge(extra, %{
          "d4h_member_id" => member.d4h_member_id,
          "status" => "ATTENDING",
          "starts_at" => iso(starts_at),
          "ends_at" => starts_at |> DateTime.add(minutes, :minute) |> iso()
        })
    }
  end

  # A row that already says what it should is left alone.
  defp update_attendance(info, member, minutes, starts_at) do
    ends_at = DateTime.add(starts_at, minutes, :minute)

    if info.status == "attending" and same_time?(info.started_at, starts_at) and
         same_time?(info.finished_at, ends_at) do
      []
    else
      [
        %ChangeSetRow{
          action: :update_attendance,
          member_id: member.id,
          d4h_record_id: info.d4h_attendance_id,
          old_value: %{
            "status" => String.upcase(info.status),
            "starts_at" => iso(info.started_at),
            "ends_at" => iso(info.finished_at)
          },
          new_value: %{
            "status" => "ATTENDING",
            "starts_at" => iso(starts_at),
            "ends_at" => iso(ends_at)
          }
        }
      ]
    end
  end

  defp publish_row(id, published) do
    %ChangeSetRow{
      action: :publish_activity,
      d4h_record_id: id,
      old_value: %{"kind" => @kind},
      new_value: %{"published" => published}
    }
  end

  defp same_time?(nil, _b), do: false
  defp same_time?(a, b), do: a |> DateTime.truncate(:second) |> DateTime.compare(b) == :eq

  defp iso(nil), do: nil

  defp iso(%DateTime{} = datetime),
    do: datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
