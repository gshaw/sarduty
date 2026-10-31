defmodule App.Report.Catalog do
  @moduledoc """
  The subjects and fields a report can read (#768): an allowlist, like the MCP tools.
  Never contact details, addresses, coordinates, letter text, or keys.

  A field is a rule's existing home, never a copy: `status` is
  `Attendance.status_word_dynamic/1`, `standing` is `Standing.dynamic/1`, `counted` is
  `Member.counted_dynamic/0`, and `not_seen(days)` is `Member.not_seen_query/4`. Each
  subject's `source` scopes its rows to the team before a query's `where` runs.
  """

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Standing
  alias App.Model.Tag
  alias App.Repo
  alias App.Report.Context
  alias App.Report.Field
  alias App.Report.Subject
  alias App.ViewModel.EquipmentItemFormViewModel

  @subjects ~w(activities attendance members awards qualifications equipment equipment_use groups)

  @doc "The subjects' names, in the order the editor lists them."
  def names, do: @subjects

  @doc "Every subject."
  def subjects, do: Enum.map(@subjects, &subject/1)

  @doc "The subject named `name`, or nil."
  def subject("activities") do
    %Subject{
      name: "activities",
      label: "Activities",
      one: "activity",
      many: "activities",
      source: &activities/1,
      fields: [
        id(),
        record("title", "Activity", :activity, :title),
        text(:ref_id, "ID", "The activity's ID."),
        %Field{
          name: "kind",
          label: "Kind",
          type: :choice,
          column: :kind,
          choices: fn _ -> activity_kinds() end
        },
        date(:started_at, "Started"),
        date(:finished_at, "Finished"),
        bool(:published, "Published"),
        list(:tags, "Tags", &tag_titles/1),
        number(
          :hours_tag_count,
          "Hours tags",
          "How many of the hours tags it has: 0, 1, or more."
        ),
        bool(
          :attendance_sent,
          "Attendance sent",
          "Whether a team admin sent its attendance from SAR Duty."
        ),
        number(:attended_count, "Attended", "How many members attended."),
        %Field{name: "attended_hours", label: "Hours", type: :hours, column: :attended_hours}
      ]
    }
  end

  def subject("attendance") do
    %Subject{
      name: "attendance",
      label: "Attendance",
      one: "row",
      many: "rows",
      source: &attendance/1,
      parents: %{"member" => {"members", :member_id}, "activity" => {"activities", :activity_id}},
      fields: [
        id(),
        parent("member", "Member", :member),
        parent("activity", "Activity", :activity),
        %Field{
          name: "status",
          label: "Status",
          type: :choice,
          column: :status,
          about: "Attended, Signed up, Absent, Can't make it, or No reply.",
          choices: fn _ -> statuses() end
        },
        date(:started_at, "Started"),
        %Field{name: "hours", label: "Hours", type: :hours, column: :hours},
        date(:replied_at, "Replied")
      ]
    }
  end

  def subject("members") do
    %Subject{
      name: "members",
      label: "Members",
      one: "member",
      many: "members",
      source: &members/1,
      fields: [
        id(),
        record("name", "Member", :member, :name),
        text(:ref_id, "ID", "The member's ID on the team."),
        text(:position, "Position"),
        date(:joined_at, "Joined"),
        %Field{
          name: "standing",
          label: "Standing",
          type: :choice,
          column: :standing,
          about: "Active, Away, Retiring, Not a person, or Retired.",
          choices: fn _ -> standings() end
        },
        bool(:counted, "Counted", "Whether SAR Duty counts them: not retiring, and a person."),
        bool(:person, "Person", "Whether they are a person, not a pager or a shared login."),
        list(:groups, "Groups", &group_titles/1),
        list(:qualifications, "Qualifications", &qualification_titles/1),
        date(:last_attended, "Last attended"),
        %Field{
          name: "not_seen",
          label: "Not seen",
          type: :bool,
          args: [:days],
          sql: &not_seen_sql/3,
          about:
            "not_seen(365): current members whose attendance clock is older than 365 days, as Needs attention counts."
        }
      ]
    }
  end

  def subject("awards") do
    %Subject{
      name: "awards",
      label: "Awards",
      one: "award",
      many: "awards",
      source: &awards/1,
      parents: %{
        "member" => {"members", :member_id},
        "qualification" => {"qualifications", :qualification_id}
      },
      fields: [
        id(),
        parent("member", "Member", :member),
        parent("qualification", "Qualification", :qualification),
        date(:starts_at, "Starts"),
        date(:ends_at, "Expires"),
        bool(:current, "Current", "Whether it has started and not ended.")
      ]
    }
  end

  def subject("qualifications") do
    %Subject{
      name: "qualifications",
      label: "Qualifications",
      one: "qualification",
      many: "qualifications",
      source: &qualifications/1,
      fields: [
        id(),
        record("title", "Qualification", :qualification, :title),
        number(
          :expires_months,
          "Lasts",
          "How many months an award lasts, or null when it never expires."
        )
      ]
    }
  end

  def subject("equipment") do
    %Subject{
      name: "equipment",
      label: "Equipment",
      one: "item",
      many: "items",
      source: &equipment/1,
      parents: %{"holder" => {"members", :member_id}},
      fields: [
        id(),
        record("title", "Item", :item, :title),
        %Field{
          name: "type",
          label: "Type",
          type: :choice,
          column: :type,
          choices: fn _ -> EquipmentItemFormViewModel.types() end
        },
        %Field{
          name: "kind",
          label: "Kind",
          type: :text,
          column: :kind,
          choices: &equipment_kinds/1
        },
        %Field{
          name: "status",
          label: "Status",
          type: :choice,
          column: :status,
          choices: fn _ -> EquipmentItemFormViewModel.statuses() end
        },
        text(:barcode, "Barcode"),
        text(:serial, "Serial"),
        text(:location, "Location"),
        date(:expires_at, "Expires"),
        parent("holder", "Held by", :member)
      ]
    }
  end

  def subject("equipment_use") do
    %Subject{
      name: "equipment_use",
      label: "Equipment use",
      one: "use",
      many: "uses",
      source: &equipment_use/1,
      parents: %{
        "activity" => {"activities", :activity_id},
        "item" => {"equipment", :equipment_item_id}
      },
      fields: [
        id(),
        parent("activity", "Activity", :activity),
        parent("item", "Item", :item),
        %Field{name: "hours", label: "Hours", type: :hours, column: :hours},
        %Field{name: "km", label: "Distance", type: :km, column: :km},
        number(:quantity, "Used", "How many of a supply were used.")
      ]
    }
  end

  def subject("groups") do
    %Subject{
      name: "groups",
      label: "Groups",
      one: "group",
      many: "groups",
      source: &groups/1,
      fields: [
        id(),
        record("title", "Group", :group, :title),
        number(:member_count, "Members", "How many current members are in it.")
      ]
    }
  end

  def subject(_name), do: nil

  @doc "The field named `name` in `subject`, or nil."
  def field(%Subject{fields: fields}, name), do: Enum.find(fields, &(&1.name == name))

  @doc "The fields the editor lists for `subject`: all but the id."
  def shown_fields(%Subject{fields: fields}), do: Enum.reject(fields, & &1.hidden)

  defp id, do: %Field{name: "id", label: "ID", type: :number, column: :id, hidden: true}

  # A field named for its column in the subject's rows.
  defp text(column, label, about \\ nil), do: plain(column, label, :text, about: about)
  defp number(column, label, about), do: plain(column, label, :number, about: about)
  defp date(column, label), do: plain(column, label, :date, [])
  defp bool(column, label, about \\ nil), do: plain(column, label, :bool, about: about)
  defp list(column, label, choices), do: plain(column, label, :list, choices: choices)

  defp plain(column, label, type, attrs) do
    struct!(
      Field,
      [name: Atom.to_string(column), label: label, type: type, column: column] ++ attrs
    )
  end

  defp record(name, label, kind, column),
    do: %Field{name: name, label: label, type: {:record, kind}, column: column, id_column: :id}

  defp parent(name, label, kind),
    do: %Field{name: name, label: label, type: {:record, kind}, parent: name}

  # The glossary's words for D4H's values.
  defp activity_kinds,
    do: [{"Incident", "incident"}, {"Exercise", "exercise"}, {"Event", "event"}]

  defp statuses,
    do: [
      {"Attended", "attended"},
      {"Signed up", "signed_up"},
      {"Absent", "absent"},
      {"Can't make it", "cant_make_it"},
      {"No reply", "no_reply"}
    ]

  # Away's text names its period; a report's choice is Away alone.
  defp standings,
    do:
      Enum.map(Standing.order(), fn
        :away -> {"Away", "away"}
        standing -> {Standing.text(standing), Atom.to_string(standing)}
      end)

  defp tag_titles(%Context{team: team}),
    do: titles(from(t in Tag, where: t.team_id == ^team.id, select: t.title))

  defp group_titles(%Context{team: team}),
    do: titles(from(g in Group, where: g.team_id == ^team.id, select: g.title))

  defp qualification_titles(%Context{team: team}),
    do: titles(from(q in Qualification, where: q.team_id == ^team.id, select: q.title))

  defp equipment_kinds(%Context{team: team}),
    do:
      titles(
        from(e in EquipmentItem,
          where: e.team_id == ^team.id and not is_nil(e.kind),
          select: e.kind
        )
      )

  defp titles(query),
    do:
      query
      |> distinct(true)
      |> Repo.all()
      |> Enum.sort_by(&String.downcase/1)
      |> Enum.map(&{&1, &1})

  # Each source selects its subject's columns, scoped to the team.

  defp activities(%Context{team: team, now: now, hours_tags: hours_tags}) do
    attended =
      now
      |> Attendance.attended()
      |> where([activity: a], a.team_id == ^team.id)
      |> group_by([r], r.activity_id)
      |> select([r], %{
        activity_id: r.activity_id,
        count: count(r.member_id, :distinct),
        minutes: sum(r.duration_in_minutes)
      })

    Activity
    |> where([a], a.team_id == ^team.id)
    |> Activity.not_deleted()
    |> join(:left, [a], t in subquery(attended), as: :attended, on: t.activity_id == a.id)
    |> select(
      ^%{
        id: dynamic([a], a.id),
        title: dynamic([a], a.title),
        ref_id: dynamic([a], a.ref_id),
        kind: dynamic([a], a.activity_kind),
        started_at: dynamic([a], a.started_at),
        finished_at: dynamic([a], a.finished_at),
        published: dynamic([a], a.is_published),
        tags: dynamic([a], a.tags),
        hours_tag_count: Activity.hours_tag_count_dynamic(hours_tags),
        attendance_sent: dynamic([a], not is_nil(a.attendance_sent_at)),
        attended_count: dynamic([attended: t], coalesce(t.count, 0)),
        attended_hours: dynamic([attended: t], coalesce(t.minutes, 0))
      }
    )
  end

  defp attendance(%Context{team: team, now: now}) do
    query =
      from(r in Attendance,
        join: a in assoc(r, :activity),
        as: :activity,
        join: m in assoc(r, :member),
        where: a.team_id == ^team.id and m.team_id == ^team.id and is_nil(a.deleted_at)
      )

    select(
      query,
      ^%{
        id: dynamic([r], r.id),
        member_id: dynamic([r], r.member_id),
        activity_id: dynamic([r], r.activity_id),
        status: Attendance.status_word_dynamic(now),
        started_at: dynamic([r, activity: a], coalesce(r.started_at, a.started_at)),
        hours: dynamic([r], r.duration_in_minutes),
        replied_at: dynamic([r], r.replied_at)
      }
    )
  end

  defp members(%Context{team: team, now: now, today: today}) do
    groups =
      from(gm in GroupMember,
        join: g in assoc(gm, :group),
        where: g.team_id == ^team.id,
        group_by: gm.member_id,
        select: %{
          member_id: gm.member_id,
          titles: fragment("json_group_array(DISTINCT ?)", g.title)
        }
      )

    qualifications =
      MemberQualificationAward
      |> where(^MemberQualificationAward.active_dynamic(now))
      |> join(:inner, [aw], q in assoc(aw, :qualification))
      |> where([_aw, q], q.team_id == ^team.id)
      |> group_by([aw], aw.member_id)
      |> select([aw, q], %{
        member_id: aw.member_id,
        titles: fragment("json_group_array(DISTINCT ?)", q.title)
      })

    Member
    |> where([m], m.team_id == ^team.id)
    |> Standing.join(team, today)
    |> join(:left, [m], l in subquery(Member.last_attended_query(team, now)),
      as: :last,
      on: l.member_id == m.id
    )
    |> join(:left, [m], g in subquery(groups), as: :groups, on: g.member_id == m.id)
    |> join(:left, [m], q in subquery(qualifications), as: :awards, on: q.member_id == m.id)
    |> select(
      ^%{
        id: dynamic([m], m.id),
        name: dynamic([m], m.name),
        ref_id: dynamic([m], m.ref_id),
        position: dynamic([m], m.position),
        joined_at: dynamic([m], m.joined_at),
        standing: Standing.dynamic(now),
        counted: Member.counted_dynamic(),
        person: dynamic([m], not m.not_a_person),
        groups: dynamic([groups: g], g.titles),
        qualifications: dynamic([awards: q], q.titles),
        last_attended: dynamic([last: l], l.last_attended_at)
      }
    )
  end

  defp awards(%Context{team: team, now: now}) do
    MemberQualificationAward
    |> join(:inner, [aw], q in assoc(aw, :qualification))
    |> join(:inner, [aw], m in assoc(aw, :member))
    |> where([_aw, q, m], q.team_id == ^team.id and m.team_id == ^team.id)
    |> select(
      ^%{
        id: dynamic([aw], aw.id),
        member_id: dynamic([aw], aw.member_id),
        qualification_id: dynamic([aw], aw.qualification_id),
        starts_at: dynamic([aw], aw.starts_at),
        ends_at: dynamic([aw], aw.ends_at),
        current: MemberQualificationAward.active_dynamic(now)
      }
    )
  end

  defp qualifications(%Context{team: team}) do
    from(q in Qualification,
      where: q.team_id == ^team.id,
      select: %{id: q.id, title: q.title, expires_months: q.expires_months_default}
    )
  end

  defp equipment(%Context{team: team}) do
    from(e in EquipmentItem,
      where: e.team_id == ^team.id,
      select: %{
        id: e.id,
        title: e.title,
        type: e.item_type,
        kind: e.kind,
        status: e.status,
        barcode: e.barcode,
        serial: e.serial,
        location: e.location_title,
        expires_at: e.expires_at,
        member_id: e.member_id
      }
    )
  end

  # `distance` is whole km: the adapter turns D4H's meters into km.
  defp equipment_use(%Context{team: team}) do
    from(u in EquipmentUsage,
      join: a in assoc(u, :activity),
      where: u.team_id == ^team.id and a.team_id == ^team.id and is_nil(a.deleted_at),
      select: %{
        id: u.id,
        activity_id: u.activity_id,
        equipment_item_id: u.equipment_item_id,
        hours: u.minutes,
        km: u.distance,
        quantity: u.used
      }
    )
  end

  defp groups(%Context{team: team, now: now}) do
    current =
      from(gm in GroupMember,
        join: m in assoc(gm, :member),
        as: :member,
        where: m.team_id == ^team.id,
        group_by: gm.group_id,
        select: %{group_id: gm.group_id, count: count(gm.member_id, :distinct)}
      )

    current = where(current, ^Member.current_dynamic(now, :member))

    from(g in Group,
      where: g.team_id == ^team.id,
      left_join: c in subquery(current),
      on: c.group_id == g.id,
      select: %{id: g.id, title: g.title, member_count: coalesce(c.count, 0)}
    )
  end

  # The members whose attendance clock is older than `days`, as Needs attention counts.
  defp not_seen_sql(table, [days], %Context{team: team, now: now}) do
    query = Member |> Member.not_seen_query(team, days, now) |> select([m], m.id)
    {sql, params} = Repo.to_sql(:all, query)
    {[table, ".\"id\" IN (", sql, ")"], params}
  end
end
