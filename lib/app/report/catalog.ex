# Experiment (list views): the experiment fields break Credo rules; not for merge.
# credo:disable-for-this-file
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
  alias App.Report.Subject
  alias App.ViewModel.EquipmentItemFormViewModel

  @subjects ~w(activities attendance members awards qualifications equipment equipment_use groups milestones)

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
        %Field{name: "attended_hours", label: "Hours", type: :hours, column: :attended_hours},
        # Experiment (list views): what the Activities list filters, searches, and sorts by.
        text(:tracking_number, "Tracking number"),
        text(:description, "Description"),
        number(:duration, "Duration", "Minutes: a chore activity's members' total."),
        scope_field("chore", "Chore", "One of the team's chore activities.", &chore_ids/2),
        scope_field("current", "Current", "Overlaps Current.", &current_ids/2),
        scope_field("recent", "Recent", "Finished in the last 30 days.", &recent_ids/2),
        scope_field(
          "missing_required_fields",
          "Missing fields",
          "A draft incident with a required field empty.",
          &missing_fields_ids/2
        ),
        scope_field(
          "primary_tag",
          "Primary hours tag",
          "Has the primary hours tag.",
          &primary_ids/2
        ),
        scope_field(
          "secondary_tag",
          "Secondary hours tag",
          "Has the secondary hours tag.",
          &secondary_ids/2
        )
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
        date(:replied_at, "Replied"),
        # Experiment (list views)
        scope_field(
          "in_period",
          "In period",
          "in_period('90d') or in_period('2026'): started in a period.",
          &attendance_in_period_ids/2,
          [:period]
        )
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
        },
        # Experiment (list views): what the Members list filters, searches, and sorts by.
        date(:left_at, "Retired"),
        bool(:current, "Not retired"),
        scope_field(
          "details_missing",
          "Details missing",
          "No phone, email, or address.",
          &details_missing_ids/2
        ),
        scope_field(
          "holds_items",
          "Holds items",
          "Holds some of the team's items.",
          &holder_ids/2
        ),
        scope_field(
          "can_log_in",
          "Can log in",
          "D4H lets them log in.",
          &access_ids(&1, &2, true)
        ),
        scope_field(
          "no_access",
          "No access",
          "D4H doesn't let them log in.",
          &access_ids(&1, &2, false)
        ),
        scope_field(
          "on_team",
          "On the team",
          "on_team('2026'): on the team at any point in the period.",
          &on_team_ids/2,
          [:period]
        ),
        %Field{
          name: "activity_count",
          label: "Activities",
          type: :number,
          args: [:period, :tag],
          sql: &summary_sql(&1, &2, &3, :activity_count)
        },
        %Field{
          name: "attended_minutes",
          label: "Duration",
          type: :hours,
          args: [:period, :tag],
          sql: &summary_sql(&1, &2, &3, :total_minutes)
        },
        %Field{
          name: "tax_hours",
          label: "Tax credit hours",
          type: :hours,
          args: [:year, :part],
          sql: &tax_hours_sql/3
        },
        %Field{
          name: "letter",
          label: "Letter",
          type: :text,
          args: [:year],
          sql: &letter_sql/3
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
        bool(:current, "Current", "Whether it has started and not ended."),
        # Experiment (list views): the awards pages' rules, from their Elixir homes.
        scope_field(
          "latest_active",
          "Held",
          "The member's latest current award of it.",
          &latest_award_ids(&1, &2, :active)
        ),
        scope_field(
          "latest_expired",
          "Expired",
          "The member's latest award, expired, with none current.",
          &latest_award_ids(&1, &2, :expired)
        ),
        scope_field(
          "expiring",
          "Expiring",
          "expiring(60): a current member's latest award of it ends in the next 60 days.",
          &expiring_ids/2,
          [:days]
        )
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
        ),
        # Experiment (list views)
        bool(:organization_owned, "Organization's"),
        %Field{
          name: "held_count",
          label: "Held",
          type: :number,
          args: [],
          sql: &held_count_sql(&1, &2, &3, :active)
        },
        %Field{
          name: "expired_count",
          label: "Expired",
          type: :number,
          args: [],
          sql: &held_count_sql(&1, &2, &3, :expired)
        }
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
        parent("holder", "Held by", :member),
        # Experiment (list views): the Equipment page's rules, from EquipmentList.
        %Field{
          name: "place",
          label: "Where",
          type: :text,
          args: [],
          sql: &equipment_text_sql(&1, &2, &3, :place)
        },
        %Field{
          name: "category",
          label: "Category",
          type: :text,
          args: [],
          sql: &equipment_text_sql(&1, &2, &3, :category)
        },
        scope_field(
          "expires_soon",
          "Expires soon",
          "Expired, or expires within the app's window.",
          &expires_soon_ids/2
        )
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
        number(:member_count, "Members", "How many current members are in it."),
        # Experiment (list views)
        bool(:organization_owned, "Organization's"),
        scope_field(
          "out_of_step",
          "Out of step",
          "Its rules would change members now, or need fixing.",
          &out_of_step_ids/2
        )
      ]
    }
  end

  # Experiment (list views): a subject an Elixir rule makes, sent to SQLite as VALUES.
  def subject("milestones") do
    %Subject{
      name: "milestones",
      label: "Milestones",
      one: "milestone",
      many: "milestones",
      source: &milestones/1,
      parents: %{"member" => {"members", :member_id}},
      fields: [
        id(),
        parent("member", "Member", :member),
        %Field{
          name: "kind",
          label: "Kind",
          type: :choice,
          column: :kind,
          choices: fn _ ->
            [{"Hours", "hours"}, {"Years", "years"}, {"Incidents", "incidents"}]
          end
        },
        number(:count, "Count", "The hours, years, or incidents reached."),
        text(:reached_on, "Reached"),
        scope_field(
          "in_period",
          "In period",
          "in_period('90d'): reached in a period.",
          &milestone_period_ids/2,
          [:period]
        )
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
    |> join(:left, [a], c in subquery(ChoreEvent.totals(team.id)),
      as: :chores,
      on: c.d4h_activity_id == a.d4h_activity_id
    )
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
        attended_hours: dynamic([attended: t], coalesce(t.minutes, 0)),
        tracking_number: dynamic([a], a.tracking_number),
        description: dynamic([a], a.description),
        duration:
          dynamic(
            [a, chores: c],
            fragment(
              "COALESCE(?, (JULIANDAY(?) - JULIANDAY(?)) * 1440.0)",
              c.minutes,
              a.finished_at,
              a.started_at
            )
          )
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
        last_attended: dynamic([last: l], l.last_attended_at),
        left_at: dynamic([m], m.left_at),
        current: Member.current_dynamic(now)
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
      select: %{
        id: q.id,
        title: q.title,
        expires_months: q.expires_months_default,
        organization_owned: q.organization_owned
      }
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
      select: %{
        id: g.id,
        title: g.title,
        member_count: coalesce(c.count, 0),
        organization_owned: g.organization_owned
      }
    )
  end

  # The members whose attendance clock is older than `days`, as Needs attention counts.
  defp not_seen_sql(table, [days], %Context{team: team, now: now}) do
    query = Member |> Member.not_seen_query(team, days, now) |> select([m], m.id)
    {sql, params} = Repo.to_sql(:all, query)
    {[table, ".\"id\" IN (", sql, ")"], params}
  end

  # Experiment (list views): a field that is an existing scope function, as
  # `id IN (the ids it keeps)`, so the rule stays in its home.
  defp scope_field(name, label, about, fun, args \\ []) do
    %Field{
      name: name,
      label: label,
      type: :bool,
      about: about,
      args: args,
      sql: fn table, args, context -> in_ids(table, fun.(context, args)) end
    }
  end

  defp in_ids(table, ids) when is_list(ids) do
    marks = ids |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")
    {["(", table, ".\"id\" IN (", marks, "))"], ids}
  end

  defp in_ids(table, query) do
    {sql, params} = Repo.to_sql(:all, query)
    {["(", table, ".\"id\" IN (", sql, "))"], params}
  end

  defp activity_ids(team), do: Activity |> where([a], a.team_id == ^team.id) |> select([a], a.id)

  defp chore_ids(%Context{team: team}, []) do
    chores = from(t in subquery(ChoreEvent.totals(team.id)), select: t.d4h_activity_id)
    where(activity_ids(team), [a], a.d4h_activity_id in subquery(chores))
  end

  defp current_ids(%Context{team: team, now: now, timezone: timezone}, []) do
    {start, finish} = Service.Period.current(now, timezone)
    team |> activity_ids() |> Activity.overlapping(start, finish)
  end

  defp recent_ids(%Context{team: team, now: now}, []),
    do: team |> activity_ids() |> Activity.finished_recently(now)

  defp missing_fields_ids(%Context{team: team}, []),
    do: team |> activity_ids() |> Activity.missing_required_fields()

  defp primary_ids(%Context{team: team, hours_tags: tags}, []),
    do: team |> activity_ids() |> Activity.tagged(tags.primary)

  defp secondary_ids(%Context{team: team, hours_tags: tags}, []),
    do: team |> activity_ids() |> Activity.tagged(tags.secondary)

  defp attendance_in_period_ids(%Context{timezone: timezone, now: now}, [period]) do
    Attendance |> Attendance.started_in(period, timezone, now) |> select([r], r.id)
  end

  defp member_ids(team), do: Member |> where([m], m.team_id == ^team.id) |> select([m], m.id)

  defp details_missing_ids(%Context{team: team, now: now}, []) do
    team
    |> member_ids()
    |> Member.current_query(now)
    |> Member.counted_query()
    |> Member.missing_details_query()
  end

  defp holder_ids(%Context{team: team}, []),
    do: where(member_ids(team), [m], m.id in subquery(EquipmentItem.holder_ids_query(team)))

  defp access_ids(%Context{team: team}, [], access?),
    do: team |> member_ids() |> Member.d4h_access_query(access?)

  # The Members list's Period filter, from MemberFilterViewModel (its rule has no model home).
  defp on_team_ids(%Context{team: team}, ["all"]), do: member_ids(team)

  defp on_team_ids(%Context{team: team, timezone: timezone, now: now}, [period]) do
    {start, finish} = Service.Period.bounds(period, timezone, now)

    team
    |> member_ids()
    |> where([m], is_nil(m.joined_at) or m.joined_at < ^finish)
    |> where([m], is_nil(m.left_at) or m.left_at >= ^start)
  end

  # The Members list's Activities and Duration columns: a count over the period and tag.
  defp summary_sql(table, [period, tag], %Context{team: team, timezone: timezone, now: now}, key) do
    # The same rows as MemberFilterViewModel's summary; the real build gives it one home.
    attended =
      now
      |> Attendance.attended()
      |> where([activity: ac], ac.team_id == ^team.id)
      |> Attendance.at_tagged(team, if(tag == "all", do: nil, else: tag))

    attended =
      if period == "all",
        do: attended,
        else: Attendance.started_in(attended, period, timezone, now)

    summary =
      from(at in attended,
        group_by: at.member_id,
        select: %{
          member_id: at.member_id,
          activity_count: count(at.id),
          total_minutes: sum(at.duration_in_minutes)
        }
      )

    {sql, params} = Repo.to_sql(:all, from(x in subquery(summary), select: x))

    {[
       "COALESCE((SELECT xs.\"",
       Atom.to_string(key),
       "\" FROM (",
       sql,
       ") xs WHERE xs.\"member_id\" = ",
       table,
       ".\"id\"), 0)"
     ], params}
  end

  # Experiment: fields an Elixir rule computes, sent to SQLite as a CASE over ids.
  defp tax_hours_sql(table, [year, part], %Context{team: team, now: now}) do
    hours = App.Operation.CountTaxCreditHours.call(team, String.to_integer(year), nil, now)
    key = String.to_existing_atom("#{part}_minutes")

    hours
    |> Enum.map(fn {member_id, counted} -> {member_id, Map.get(counted, key, 0)} end)
    |> case_sql(table, 0)
  end

  defp letter_sql(table, [year], %Context{team: team, now: now}) do
    year = String.to_integer(year)
    hours = App.Operation.CountTaxCreditHours.call(team, year, nil, now)

    from(l in App.Model.TaxCreditLetter,
      join: m in assoc(l, :member),
      where: m.team_id == ^team.id and l.year == ^year
    )
    |> Repo.all()
    |> Enum.map(fn letter ->
      counted = App.Operation.CountTaxCreditHours.get(hours, letter.member_id)
      status = App.Model.TaxCreditLetter.hours_status(letter, counted, now, team.timezone)
      {letter.member_id, if(status == :changed, do: "changed", else: "made")}
    end)
    |> case_sql(table, "none")
  end

  defp case_sql([], _table, default), do: {["?"], [default]}

  defp case_sql(pairs, table, default) do
    whens = Enum.map(pairs, fn _ -> " WHEN ? THEN ?" end)
    params = Enum.flat_map(pairs, fn {id, value} -> [id, value] end)
    {["(CASE ", table, ".\"id\"", whens, " ELSE ? END)"], params ++ [default]}
  end

  defp out_of_step_ids(%Context{team: team}, []) do
    context = App.Operation.BuildGroupRulePreview.load(team)

    ruled =
      team.id |> App.Model.GroupRule.ruled_d4h_group_ids_query() |> Repo.all() |> MapSet.new()

    Group
    |> where([g], g.team_id == ^team.id)
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(ruled, &1.d4h_group_id))
    |> Enum.filter(fn group ->
      preview = App.Operation.BuildGroupRulePreview.preview(context, team, group)
      preview.problems != [] or preview.to_add != [] or preview.to_remove != []
    end)
    |> Enum.map(& &1.id)
  end

  # Each qualification's awards split as MemberQualificationAward.split_by_member/2 does.
  defp split_awards(%Context{team: team, now: now}) do
    MemberQualificationAward
    |> join(:inner, [a], q in assoc(a, :qualification))
    |> where([a, q], q.team_id == ^team.id)
    |> order_by([a], desc: a.starts_at)
    |> Repo.all()
    |> Enum.group_by(& &1.qualification_id)
    |> Map.new(fn {id, awards} -> {id, MemberQualificationAward.split_by_member(awards, now)} end)
  end

  defp latest_award_ids(context, [], part) do
    context
    |> split_awards()
    |> Enum.flat_map(fn {_id, {active, expired}} ->
      if part == :active, do: active, else: expired
    end)
    |> Enum.map(& &1.id)
  end

  defp expiring_ids(%Context{team: team, now: now}, [days]) do
    days = if is_binary(days), do: String.to_integer(days), else: days

    team.id
    |> MemberQualificationAward.expiring(now, DateTime.add(now, days, :day))
    |> Enum.map(& &1.award_id)
  end

  defp held_count_sql(table, [], context, part) do
    context
    |> split_awards()
    |> Enum.map(fn {id, {active, expired}} ->
      {id, length(if part == :active, do: active, else: expired)}
    end)
    |> case_sql(table, 0)
  end

  defp equipment_rows(%Context{team: team}),
    do: team.id |> EquipmentItem.get_all() |> App.ViewData.EquipmentList.rows()

  defp equipment_text_sql(table, [], context, :place) do
    context |> equipment_rows() |> Enum.map(&{&1.item.id, &1.place}) |> case_sql(table, nil)
  end

  defp equipment_text_sql(table, [], context, :category) do
    context
    |> equipment_rows()
    |> Enum.map(&{&1.item.id, App.ViewData.EquipmentList.category(&1.item)})
    |> case_sql(table, nil)
  end

  defp expires_soon_ids(%Context{team: team, now: now}, []) do
    team.id
    |> EquipmentItem.get_all()
    |> Enum.filter(&(App.Operation.BuildGroupRulePreview.expiry(&1.expires_at, now) != nil))
    |> Enum.map(& &1.id)
  end

  defp milestone_rows(%Context{team: team, now: now}),
    do: team |> App.ViewData.MemberMilestones.for_team(now) |> Enum.with_index(1)

  defp milestones(context) do
    rows =
      context
      |> milestone_rows()
      |> Enum.map(fn {m, i} ->
        %{
          id: i,
          member_id: m.member.id,
          kind: Atom.to_string(m.kind),
          count: m.count,
          reached_on: Date.to_iso8601(m.on)
        }
      end)

    rows =
      if rows == [], do: [%{id: 0, member_id: 0, kind: "", count: 0, reached_on: ""}], else: rows

    types = %{
      id: :integer,
      member_id: :integer,
      kind: :string,
      count: :integer,
      reached_on: :string
    }

    from(v in values(rows, types),
      where: v.id > 0,
      select: %{
        id: v.id,
        member_id: v.member_id,
        kind: v.kind,
        count: v.count,
        reached_on: v.reached_on
      }
    )
  end

  defp milestone_period_ids(%Context{} = context, [period]) do
    rows = milestone_rows(context)
    options = %App.ViewModel.MilestoneFilterViewModel{when: period}

    kept =
      rows
      |> Enum.map(&elem(&1, 0))
      |> App.ViewModel.MilestoneFilterViewModel.filter(options, context.timezone, context.now)

    kept = MapSet.new(kept)
    for {m, i} <- rows, MapSet.member?(kept, m), do: i
  end
end
