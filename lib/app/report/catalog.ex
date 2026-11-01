defmodule App.Report.Catalog do
  @moduledoc """
  The subjects and fields a report can read (#768): an allowlist, like the MCP tools.
  Never contact details, addresses, coordinates, letter text, or keys.

  A field is a rule's existing home, never a copy: `status` is
  `Attendance.status_word_dynamic/1`, `standing` is `Standing.dynamic/1`, `counted` is
  `Member.counted_dynamic/0`, and `not_seen(days)` is `Member.not_seen_query/4`. A field
  with a `query` is that rule's own query of ids (#784), such as `current`, which is
  `Activity.overlapping/3` over Current. Each subject's `source` scopes its rows to the
  team before a query's `where` runs.
  """

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.ChoreEvent
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
  alias App.Report.Source
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
      fields: activity_fields()
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
      fields: member_fields()
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

  defp activity_fields do
    [
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
    ] ++ activity_rule_fields()
  end

  # What Activities searches, sorts, and filters by (#784).
  defp activity_rule_fields do
    [
      text(:tracking_number, "Tracking number"),
      text(:description, "Description"),
      %Field{
        name: "duration",
        label: "Duration",
        type: :hours,
        column: :duration,
        about: "How long it ran: a chore activity's, its members' chores."
      },
      bool(:chore, "Chore", "One of the team's chore activities."),
      rule("current", "Current", "Within 7 days of today, as Activities' Current.", &current/2),
      rule(
        "recent",
        "Recent",
        "Started in the last 30 days and finished, as Activities' Last 30 days.",
        &recent/2
      ),
      rule(
        "missing_required_fields",
        "Missing fields",
        "A required field of its kind is empty.",
        &missing_fields/2
      )
    ]
  end

  defp member_fields do
    [
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
      date(:left_at, "Left"),
      bool(:current, "Not retired", "On the team now: every member but the retired.")
    ] ++ member_rule_fields() ++ member_list_fields()
  end

  # Rules over a time frame: Needs attention's not_seen, and Members' Period (#784).
  defp member_rule_fields do
    [
      %Field{
        name: "not_seen",
        label: "Not seen",
        type: :bool,
        args: [:days],
        query: &not_seen/2,
        about:
          "not_seen(365): current members whose attendance clock is older than 365 days, as Needs attention counts."
      },
      %Field{
        name: "on_team",
        label: "On the team",
        type: :bool,
        args: [:period],
        query: &on_team/2,
        about: "on_team('2026'): on the team at any point in the period, as Members' Period."
      }
    ]
  end

  # What Members shows and filters by (#784).
  defp member_list_fields do
    [
      %Field{
        name: "activity_count",
        label: "Activities",
        type: :number,
        args: [:period, :tag],
        sql: &totals_sql(&1, &2, &3, :activity_count),
        about: "activity_count('2026', 'all'): activities attended in the period, with the tag."
      },
      %Field{
        name: "attended_minutes",
        label: "Hours",
        type: :hours,
        args: [:period, :tag],
        sql: &totals_sql(&1, &2, &3, :total_minutes),
        about: "attended_minutes('2026', 'all'): hours attended in the period, with the tag."
      },
      rule(
        "details_missing",
        "Details missing",
        "A current member with no phone, email, or address on file.",
        &details_missing/2
      ),
      rule("holds_items", "Holds items", "Holds any of the team's items.", &holds_items/2),
      rule(
        "can_log_in",
        "Can log in",
        "Can log in to the team's records.",
        &access(&1, &2, true)
      ),
      rule("no_access", "No access", "Has No access: cannot log in.", &access(&1, &2, false))
    ]
  end

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

  # A field that is a rule's own query of ids: true for the rows it keeps.
  defp rule(name, label, about, query),
    do: %Field{name: name, label: label, type: :bool, about: about, query: query}

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

  @doc "The team's tags' titles, as choices."
  def tag_titles(%Context{team: team}),
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

  # ABCSize skips what sits inside a select, and these columns were one until #784.
  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp activities(%Context{team: team, hours_tags: hours_tags} = context) do
    %Source{
      query: Activity |> where([a], a.team_id == ^team.id) |> Activity.not_deleted(),
      joins: activity_joins(context),
      needs: %{
        attended_count: [:attended],
        attended_hours: [:attended],
        duration: [:chores],
        chore: [:chores]
      },
      fields: %{
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
        attended_hours: dynamic([attended: t], coalesce(t.minutes, 0)),
        tracking_number: dynamic([a], a.tracking_number),
        description: dynamic([a], a.description),
        duration: Activity.duration_dynamic(),
        chore: dynamic([chores: c], not is_nil(c.d4h_activity_id))
      }
    }
  end

  defp activity_joins(%Context{team: team, now: now}) do
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

    %{
      attended:
        &join(&1, :left, [a], t in subquery(attended), as: :attended, on: t.activity_id == a.id),
      chores:
        &join(&1, :left, [a], c in subquery(ChoreEvent.totals(team.id)),
          as: :chores,
          on: c.d4h_activity_id == a.d4h_activity_id
        )
    }
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

  # One dynamic per column, as activities/1 has.
  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp members(%Context{team: team, now: now} = context) do
    %Source{
      query: where(Member, [m], m.team_id == ^team.id),
      joins: member_joins(context),
      needs: %{
        standing: [:standing],
        groups: [:groups],
        qualifications: [:awards],
        last_attended: [:last]
      },
      fields: %{
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
        last_attended: dynamic([last: l], l.last_attended_at),
        left_at: dynamic([m], m.left_at),
        current: Member.current_dynamic(now)
      }
    }
  end

  defp member_joins(%Context{team: team, now: now, today: today}) do
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

    %{
      standing: &Standing.join(&1, team, today),
      last:
        &join(&1, :left, [m], l in subquery(Member.last_attended_query(team, now)),
          as: :last,
          on: l.member_id == m.id
        ),
      groups: &join(&1, :left, [m], g in subquery(groups), as: :groups, on: g.member_id == m.id),
      awards:
        &join(&1, :left, [m], q in subquery(qualifications), as: :awards, on: q.member_id == m.id)
    }
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

  # Rules' own queries of ids, each scoped to the team.

  defp team_activities(team),
    do: Activity |> where([a], a.team_id == ^team.id) |> select([a], a.id)

  defp team_members(team), do: Member |> where([m], m.team_id == ^team.id) |> select([m], m.id)

  defp current(%Context{team: team, now: now, timezone: timezone}, []) do
    {start, finish} = Service.Period.current(now, timezone)
    team |> team_activities() |> Activity.overlapping(start, finish)
  end

  defp recent(%Context{team: team, now: now, timezone: timezone}, []),
    do: team |> team_activities() |> Activity.finished_recently(now, timezone)

  defp missing_fields(%Context{team: team}, []),
    do: team |> team_activities() |> Activity.missing_required_fields()

  # The members whose attendance clock is older than `days`, as Needs attention counts.
  defp not_seen(%Context{team: team, now: now}, [days]),
    do: Member |> Member.not_seen_query(team, days, now) |> select([m], m.id)

  defp on_team(%Context{team: team, now: now, timezone: timezone}, [period]),
    do: team |> team_members() |> Member.on_team_query(period, timezone, now)

  defp details_missing(%Context{team: team, now: now}, []),
    do: team |> team_members() |> Member.details_missing_query(now)

  defp holds_items(%Context{team: team}, []),
    do: where(team_members(team), [m], m.id in subquery(EquipmentItem.holder_ids_query(team)))

  defp access(%Context{team: team}, [], access?),
    do: team |> team_members() |> Member.d4h_access_query(access?)

  # A member's attended activities or minutes in a period, with a tag: 0 for none.
  defp totals_sql(table, [period, tag], %Context{team: team, now: now}, key) do
    query = from(t in subquery(Attendance.member_totals_query(team, period, tag, now)), select: t)
    {sql, params} = Repo.to_sql(:all, query)
    column = Atom.to_string(key)

    {[
       "COALESCE((SELECT t.\"",
       column,
       "\" FROM (",
       sql,
       ") AS t WHERE t.\"member_id\" = ",
       table,
       ".\"id\"), 0)"
     ], params}
  end
end
