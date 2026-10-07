defmodule App.ViewData.ChangeHistory do
  import Ecto.Query

  alias App.Model.ChangeSetRow
  alias App.Model.D4HChange
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  # A member's or an activity's history (#174, step 3): what SAR Duty changed in D4H,
  # from applied change set rows, and what the sync saw change in D4H, from `d4h_changes`.
  # Each entry is a map: `at`, `by` (`:sar_duty` or `:d4h`), `seen_after` for a D4H
  # change (the last refresh before it), `text`, and for SAR Duty's changes `source`,
  # `applied_by`, and `reason`. Newest first.

  @limit 200

  def for_member(%Team{} = team, %Member{team_id: team_id} = member)
      when team_id == team.id do
    changes = D4HChange.for_member(team.id, member.id, @limit)

    rows =
      ChangeSetRow
      |> where([r], r.team_id == ^team.id and r.member_id == ^member.id)
      |> applied_rows()

    merge(changes, rows, :member, team.timezone)
  end

  def for_activity(%Team{} = team, %{team_id: team_id} = activity) when team_id == team.id do
    changes = D4HChange.for_activity(team.id, activity.id, @limit)

    rows =
      ChangeSetRow
      |> join(:inner, [r], s in assoc(r, :change_set))
      |> where([r, s], r.team_id == ^team.id and s.activity_id == ^activity.id)
      |> applied_rows()

    merge(changes, rows, :activity, team.timezone)
  end

  defp applied_rows(query) do
    query
    |> where([r], r.status == :applied)
    |> order_by([r], desc: r.applied_at, desc: r.id)
    |> limit(@limit)
    |> preload([:member, change_set: [:activity, :group, :applied_by_user]])
    |> Repo.all()
  end

  defp merge(changes, rows, page, tz) do
    (Enum.map(changes, &d4h_entry(&1, page, tz)) ++ Enum.map(rows, &sar_duty_entry(&1, page)))
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(@limit)
  end

  defp d4h_entry(%D4HChange{} = change, page, tz) do
    %{
      id: "d4h-#{change.id}",
      at: change.seen_at,
      seen_after: change.seen_after,
      by: :d4h,
      kind: change.record_kind,
      text: describe(change, page, tz)
    }
  end

  defp sar_duty_entry(%ChangeSetRow{} = row, page) do
    %{
      id: "row-#{row.id}",
      at: row.applied_at,
      seen_after: nil,
      by: :sar_duty,
      kind:
        if(row.action in [:update_attendance, :create_attendance],
          do: :attendance,
          else: :group_membership
        ),
      source: row.change_set.source,
      applied_by: row.change_set.applied_by_user && row.change_set.applied_by_user.email,
      reason: row.reason,
      text: describe_row(row, page)
    }
  end

  @doc """
  One D4H change as a sentence, with times in time zone `tz`. `page` is `:member` or
  `:activity`, the page it shows on, which decides whether it names the activity or the
  member. The change's `activity` or `member` must be preloaded for attendance.
  """
  def describe(%D4HChange{record_kind: :member, action: :added}, _page, _tz), do: "Added to D4H"

  def describe(%D4HChange{record_kind: :member, action: :changed} = c, _page, tz),
    do: c.fields |> Enum.map(&member_field(&1, c, tz)) |> Enum.uniq() |> sentences()

  def describe(%D4HChange{record_kind: :activity, action: :added}, _page, _tz), do: "Added to D4H"

  def describe(%D4HChange{record_kind: :activity, action: :changed} = c, _page, tz),
    do: c.fields |> Enum.map(&activity_field(&1, c, tz)) |> sentences()

  def describe(%D4HChange{record_kind: :attendance} = c, page, _tz) do
    who = attendance_subject(c, page)

    case c.action do
      :added -> "#{who} added to attendance as #{status(c.new_value["status"])}"
      :removed -> "#{who} removed from attendance"
      :changed -> "#{who} attendance changed: " <> attendance_changes(c)
    end
  end

  def describe(%D4HChange{record_kind: :award, action: :added} = c, _page, tz),
    do: "#{qualification(c)} awarded. #{expiry(c.new_value["ends_at"], tz)}"

  def describe(%D4HChange{record_kind: :award, action: :removed} = c, _page, _tz),
    do: "#{qualification(c)} removed from D4H"

  def describe(%D4HChange{record_kind: :award, action: :changed} = c, _page, tz) do
    if "ends_at" in c.fields,
      do: "#{qualification(c)} expiry changed. #{expiry(c.new_value["ends_at"], tz)}",
      else: "#{qualification(c)} start date changed to #{day(c.new_value["starts_at"], tz)}"
  end

  def describe(%D4HChange{record_kind: :group_membership, action: :added} = c, _page, _tz),
    do: "Added to the #{group(c)} group"

  def describe(%D4HChange{record_kind: :group_membership, action: :removed} = c, _page, _tz),
    do: "Removed from the #{group(c)} group"

  defp member_field(field, _c, _tz) when field in ~w(email phone address),
    do: "Contact details changed"

  defp member_field("name", c, _tz), do: "Name changed from #{from_to(c, "name")}"
  defp member_field("position", c, _tz), do: "Position changed from #{from_to(c, "position")}"

  defp member_field("d4h_status", c, _tz),
    do: "Status changed from #{from_to(c, "d4h_status", &member_status/1)}"

  defp member_field("d4h_permission", c, _tz),
    do: "D4H access changed from #{from_to(c, "d4h_permission", &permission/1)}"

  defp member_field("joined_at", c, tz),
    do: "Joined date changed to #{day(c.new_value["joined_at"], tz)}"

  defp member_field("left_at", c, tz) do
    case c.new_value["left_at"] do
      nil -> "Back on the team"
      left_at -> "Left the team on #{day(left_at, tz)}"
    end
  end

  defp activity_field("title", c, _tz), do: "Title changed from #{from_to(c, "title")}"

  defp activity_field("started_at", c, tz),
    do: "Start changed to #{time(c.new_value["started_at"], tz)}"

  defp activity_field("finished_at", c, tz),
    do: "End changed to #{time(c.new_value["finished_at"], tz)}"

  defp activity_field("is_published", c, _tz),
    do: if(c.new_value["is_published"], do: "Published", else: "No longer published")

  defp activity_field("tags", c, _tz) do
    case c.new_value["tags"] do
      tags when tags in [nil, []] -> "Tags removed"
      tags -> "Tags changed to #{Enum.join(tags, ", ")}"
    end
  end

  defp activity_field("deleted_at", c, _tz),
    do: if(c.new_value["deleted_at"], do: "Deleted in D4H", else: "Back in D4H")

  defp attendance_subject(%D4HChange{activity: %{title: title}}, :member), do: title
  defp attendance_subject(%D4HChange{member: %{name: name}}, :activity), do: name
  defp attendance_subject(_c, _page), do: "Attendance"

  defp attendance_changes(c) do
    status = if "status" in c.fields, do: [status(c.new_value["status"])], else: []

    times =
      if Enum.any?(~w(started_at finished_at), &(&1 in c.fields)),
        do: ["times changed"],
        else: []

    hours =
      if "duration_in_minutes" in c.fields and times == [],
        do: ["hours changed"],
        else: []

    Enum.join(status ++ times ++ hours, ", ")
  end

  @doc "One change SAR Duty applied, as a sentence."
  def describe_row(%ChangeSetRow{action: action} = row, page)
      when action in [:update_attendance, :create_attendance] do
    subject =
      case page do
        :member -> row.change_set.activity && row.change_set.activity.title
        :activity -> row.member && row.member.name
      end

    "#{subject || "Attendance"} set to #{status(row.new_value["status"])}"
  end

  def describe_row(%ChangeSetRow{action: :add_group_member} = row, _page),
    do: "Added to the #{row_group(row)} group"

  def describe_row(%ChangeSetRow{action: :remove_group_member} = row, _page),
    do: "Removed from the #{row_group(row)} group"

  defp row_group(%ChangeSetRow{change_set: %{group: %{title: title}}}), do: title
  defp row_group(_row), do: "deleted"

  @doc "Where a change set came from, as people say it."
  def source_label(:door), do: "attendance link"
  def source_label(:group_rule), do: "group rule"
  def source_label(:attendance_import), do: "import attendance"
  def source_label(:agent), do: "AI agent"

  defp qualification(%D4HChange{label: label}) when is_binary(label), do: label
  defp qualification(_c), do: "A qualification"

  defp group(%D4HChange{label: label}) when is_binary(label), do: label
  defp group(_c), do: "deleted"

  defp expiry(nil, _tz), do: "No expiry."
  defp expiry(ends_at, tz), do: "Expires #{day(ends_at, tz)}."

  defp from_to(c, field, label \\ &blank/1),
    do: "#{label.(c.old_value[field])} to #{label.(c.new_value[field])}"

  defp blank(nil), do: "none"
  defp blank(""), do: "none"
  defp blank(value), do: to_string(value)

  defp member_status(nil), do: "none"
  defp member_status(status), do: status |> String.downcase() |> String.replace("_", " ")

  defp permission(nil), do: "none"
  defp permission(level), do: Member.permission_label(level)

  # The copy holds D4H's status lowercased and change sets hold it as D4H sends it.
  defp status(nil), do: "unknown"

  defp status(status) do
    case String.downcase(status) do
      "attending" -> "attended"
      other -> String.replace(other, "_", " ")
    end
  end

  # Values are stored as ISO 8601 in UTC and shown in the team's time zone.
  defp day(nil, _tz), do: "none"
  defp day(iso, tz), do: iso |> parse() |> Service.Format.date_short(tz)

  defp time(nil, _tz), do: "none"
  defp time(iso, tz), do: iso |> parse() |> Service.Format.datetime_short(tz)

  defp parse(iso) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(iso)
    datetime
  end

  defp sentences(parts), do: Enum.join(parts, ". ")
end
