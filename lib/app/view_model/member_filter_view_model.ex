defmodule App.ViewModel.MemberFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Attendance
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Repo
  alias App.ViewData.TeamAttention

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :when, :string
    field :details, :string
    field :attended, :string
    field :standing, :string
    field :group, :integer
    field :activity_tag, :string
    field :page, :integer
    field :sort, :string
  end

  # "missing": current members with no mobile phone or no email (#205).
  def details_kinds, do: [{"All", "all"}, {"Missing", "missing"}]

  # Members not at an activity in this many days (#247): every time frame the team
  # setting offers.
  def attended_kinds,
    do: [
      {"Any time", "all"}
      | Enum.map(Team.not_seen_days(), &{"Not in #{TeamAttention.period(&1)}", "#{&1}"})
    ]

  @standings [
    {"Active", "active"},
    {"Away", "away"},
    {"Not a person", "not_a_person"},
    {"Retired", "retired"}
  ]

  @doc """
  The Standing filter (#366): Not retired, the default, is every member but the retired,
  and All adds them. Its value stays `"current"`. The attendance check can watch several standings, as
  `"active,away"`; that value gets an option of its own, "Active or away", when it's the
  one shown.
  """
  def standing_kinds(current \\ nil) do
    combined =
      case standings(current) do
        [_, _ | _] = several -> [{several |> Enum.map(&label/1) |> or_list(), current}]
        _one_or_none -> []
      end

    Enum.concat([[{"Not retired", "current"}], @standings, combined, [{"All", "all"}]])
  end

  @doc "Whether the Standing filter `value` can show retired members."
  def shows_retired?(value), do: value == "all" or "retired" in standings(value)

  defp label(standing), do: Enum.find_value(@standings, fn {l, v} -> v == standing && l end)

  defp or_list([first | rest]),
    do: Enum.join([first | Enum.map(rest, &String.downcase/1)], " or ")

  defp standings(value) when value in [nil, "", "current", "all"], do: []
  defp standings(value), do: String.split(value, ",")

  def sort_kinds,
    do: %{
      "Name" => "name",
      "Role" => "role",
      "ID" => "id",
      "Joined ↑" => "date",
      "Joined ↓" => "date-",
      "Retired ↑" => "retired",
      "Retired ↓" => "retired-",
      "Duration ↓" => "duration-",
      "Duration ↑" => "duration",
      "Activities ↓" => "activities-",
      "Activities ↑" => "activities",
      "Standing ↑" => "standing",
      "Standing ↓" => "standing-",
      "Last attended ↑" => "attended",
      "Last attended ↓" => "attended-"
    }

  # The team's groups, by name, for the Group filter (#350).
  def group_kinds(team), do: team.id |> Group.get_all() |> Enum.map(&{&1.title, &1.id})

  # The team's tags, for the Tag filter: Activities and Duration count only the
  # activities with the tag, such as 20 hours of rope rescue a year.
  def activity_tag_kinds(team), do: team.id |> Tag.titles() |> Enum.map(&{&1, &1})

  @doc """
  The Period filter (#367): All, the last 30 to 365 days as `"90d"`, then each year with
  attendance as `"2026"`, so old `when=2026` links still open the same list.
  """
  def when_kinds(team) do
    years =
      DateTime.utc_now()
      |> Attendance.attended()
      |> where([activity: ac], ac.team_id == ^team.id)
      |> Attendance.years(team.timezone)
      |> Enum.map(&Integer.to_string/1)

    [{"All", "all"}] ++
      Service.Period.rolling_kinds() ++
      Enum.map(years, fn y -> {y, y} end)
  end

  def current_year, do: Date.utc_today().year |> Integer.to_string()

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  def build_paginated_content(team, filter_options, now \\ DateTime.utc_now()) do
    team
    |> build_query(filter_options, now)
    |> Repo.paginate(page: filter_options.page)
  end

  @doc """
  How many members the list shows for `params`, from the same query, so a link to the
  list and its count always match (the home page's attendance check, #366).
  """
  def count(team, params, now \\ DateTime.utc_now()) do
    {:ok, filter_options, _changeset} = validate(params)
    team |> filter_query(filter_options, now) |> Repo.count_entries()
  end

  defp build_query(team, filter_options, now) do
    team
    |> filter_query(filter_options, now)
    |> join_attendance_summary(team, filter_options, now)
    |> join_last_attended(team, now)
    |> join_clock(team, now)
    |> sort(filter_options.sort, now)
    |> select_member_with_attendance()
  end

  # The members the filters keep, with only the joins a filter reads, so count/3 skips
  # the summary and clock joins that never change which rows match.
  defp filter_query(team, filter_options, now) do
    Member
    |> Member.scope(team_id: team.id)
    |> scope(q: filter_options.q)
    |> scope(when: filter_options.when, timezone: team.timezone, now: now)
    |> scope(details: filter_options.details)
    |> scope(attended: filter_options.attended, team: team, now: now)
    |> scope(group: filter_options.group, team: team)
    |> join_away(team, now)
    |> scope(standing: filter_options.standing, now: now)
  end

  defp build_new do
    %__MODULE__{
      when: current_year(),
      details: "all",
      attended: "all",
      standing: "current",
      sort: "name"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [
      :q,
      :when,
      :details,
      :attended,
      :standing,
      :group,
      :activity_tag,
      :page,
      :sort
    ])
    |> Field.truncate(:q, max_length: 100)
    |> Field.truncate(:activity_tag, max_length: 100)
    |> validate_kind(:details, details_kinds())
    |> validate_kind(:attended, attended_kinds())
    |> validate_standing()
    |> App.Validate.Period.call(:when)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:page, greater_than_or_equal_to: 1)
  end

  defp validate_standing(changeset) do
    known = Enum.map(@standings, &elem(&1, 1))
    value = get_field(changeset, :standing)

    if value in [nil, "current", "all"] or value |> standings() |> Enum.all?(&(&1 in known)),
      do: changeset,
      else: add_error(changeset, :standing, "is invalid")
  end

  # Retired wins over the rest, then not a person, as MemberAwayPeriod.standing/4.
  defp or_standing("active", acc, current),
    do:
      dynamic(
        [m, away: w],
        ^acc or (^current and not m.not_a_person and is_nil(w.away_until))
      )

  defp or_standing("away", acc, current),
    do:
      dynamic(
        [m, away: w],
        ^acc or (^current and not m.not_a_person and not is_nil(w.away_until))
      )

  defp or_standing("not_a_person", acc, current),
    do: dynamic([m], ^acc or (^current and m.not_a_person))

  defp or_standing("retired", acc, current), do: dynamic(^acc or not (^current))

  defp validate_kind(changeset, field, kinds),
    do: validate_inclusion(changeset, field, Enum.map(kinds, &elem(&1, 1)))

  defp join_attendance_summary(query, team, filter_options, now) do
    from(
      m in query,
      left_join: a in subquery(build_attendance_summary(team, filter_options, now)),
      as: :summary,
      on: m.id == a.member_id
    )
  end

  defp build_attendance_summary(team, filter_options, now) do
    now
    |> Attendance.attended()
    |> where([activity: ac], ac.team_id == ^team.id)
    |> group_by([at], at.member_id)
    |> select([at], %{
      member_id: at.member_id,
      activity_count: count(at.id),
      total_minutes: sum(at.duration_in_minutes)
    })
    |> started_in(filter_options.when, team.timezone, now)
    |> Attendance.at_tagged(team, filter_options.activity_tag)
  end

  defp started_in(query, period, _timezone, _now) when period in [nil, "all"], do: query

  defp started_in(query, period, timezone, now),
    do: Attendance.started_in(query, period, timezone, now)

  defp join_last_attended(query, team, now) do
    from(
      m in query,
      left_join: l in subquery(Member.last_attended_query(team, now)),
      as: :last_attended,
      on: m.id == l.member_id
    )
  end

  defp join_away(query, team, now) do
    today = Service.Period.today(now, team.timezone)

    from(
      m in query,
      left_join: w in subquery(MemberAwayPeriod.away_query(team, today)),
      as: :away,
      on: m.id == w.member_id
    )
  end

  # Where each member's attendance clock starts (#366): their latest check-in, and the
  # end of their latest away period that has started.
  defp join_clock(query, team, now) do
    today = Service.Period.today(now, team.timezone)

    last_away =
      from p in MemberAwayPeriod,
        where: p.team_id == ^team.id and p.starts_on <= ^today,
        group_by: p.member_id,
        select: %{member_id: p.member_id, ends_on: max(p.ends_on)}

    from(
      m in query,
      left_join: la in subquery(last_away),
      as: :last_away,
      on: m.id == la.member_id,
      left_join: lc in subquery(MemberCheckIn.latest_query(team)),
      as: :last_check_in,
      on: m.id == lc.member_id
    )
  end

  defp select_member_with_attendance(query) do
    from(
      [m, summary: a, last_attended: l, away: w, last_away: la, last_check_in: lc] in query,
      select: %{
        member: m,
        activity_count: fragment("? as activity_count", coalesce(a.activity_count, 0)),
        total_minutes: fragment("? as total_minutes", coalesce(a.total_minutes, 0)),
        last_attended_at: type(l.last_attended_at, :utc_datetime),
        away_until: type(w.away_until, :date),
        away_ends_on: type(la.ends_on, :date),
        checked_in_on: type(lc.checked_in_on, :date)
      }
    )
  end

  defp scope(q, q: nil), do: q
  defp scope(q, q: ""), do: q

  defp scope(q, q: search_filter) do
    # https://dev.to/ivor/beware-ectos-orwhere-pitfall-50bb
    subquery =
      Member
      |> or_where([r], like(r.name, ^"%#{search_filter}%"))
      |> or_where([r], like(r.position, ^"%#{search_filter}%"))
      |> or_where([r], like(r.ref_id, ^"%#{search_filter}%"))
      |> select([:id])

    where(q, [r], r.id in subquery(subquery))
  end

  defp scope(q, when: "all", timezone: _, now: _), do: q
  defp scope(q, when: nil, timezone: _, now: _), do: q

  # Members on the team at any point in the period.
  defp scope(q, when: period, timezone: timezone, now: now) when is_binary(period) do
    {start, finish} = Service.Period.bounds(period, timezone, now)

    q
    |> where([m], m.joined_at < ^finish)
    |> where([m], is_nil(m.left_at) or m.left_at >= ^start)
  end

  defp scope(q, details: "missing"),
    do:
      q
      |> Member.current_query(DateTime.utc_now())
      |> Member.people_query()
      |> Member.missing_details_query()

  defp scope(q, details: _all), do: q

  defp scope(q, attended: nil, team: _team, now: _now), do: q
  defp scope(q, attended: "all", team: _team, now: _now), do: q

  defp scope(q, attended: days, team: team, now: now),
    do: Member.not_seen_query(q, team, String.to_integer(days), now)

  defp scope(q, group: nil, team: _team), do: q

  defp scope(q, group: group_id, team: team),
    do: where(q, [m], m.id in subquery(GroupMember.member_ids_query(team.id, group_id)))

  defp scope(q, standing: "all", now: _now), do: q

  defp scope(q, standing: value, now: now) when value in [nil, "current"],
    do: Member.current_query(q, now)

  defp scope(q, standing: value, now: now) do
    current = Member.current_dynamic(now)
    condition = value |> standings() |> Enum.reduce(false, &or_standing(&1, &2, current))
    where(q, ^condition)
  end

  defp scope(q, sort: "name"), do: order_by(q, [r], asc: r.name)
  defp scope(q, sort: "role"), do: order_by(q, [r], asc_nulls_last: r.position)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc_nulls_last: r.ref_id)
  defp scope(q, sort: "date-"), do: order_by(q, [r], desc: r.joined_at)
  defp scope(q, sort: "date"), do: order_by(q, [r], asc: r.joined_at)
  defp scope(q, sort: "retired-"), do: order_by(q, [r], desc_nulls_last: r.left_at)
  defp scope(q, sort: "retired"), do: order_by(q, [r], asc_nulls_last: r.left_at)
  defp scope(q, sort: "duration-"), do: order_by(q, [r], desc: fragment("total_minutes"))
  defp scope(q, sort: "duration"), do: order_by(q, [r], asc: fragment("total_minutes"))

  defp scope(q, sort: "activities-"),
    do: order_by(q, [r], desc: fragment("activity_count"), asc: r.name)

  defp scope(q, sort: "activities"),
    do: order_by(q, [r], asc: fragment("activity_count"), asc: r.name)

  # By the day an away member is back, soonest first going up; everyone else after, and
  # retired members last either way. Retired and not a person win over an away period,
  # as in the Standing column, so a retired member sorts by no date.
  defp scope(q, sort: "standing"),
    do:
      order_by(q, [r, away: w],
        asc_nulls_last:
          fragment("CASE WHEN ? THEN NULL ELSE ? END", r.not_a_person, w.away_until),
        desc: r.not_a_person,
        asc: r.name
      )

  defp scope(q, sort: "standing-"),
    do:
      order_by(q, [r, away: w],
        desc_nulls_last:
          fragment("CASE WHEN ? THEN NULL ELSE ? END", r.not_a_person, w.away_until),
        desc: r.not_a_person,
        asc: r.name
      )

  # Never attended comes first going up: the members furthest from their last activity.
  defp scope(q, sort: "attended"),
    do: order_by(q, [r, last_attended: l], asc_nulls_first: l.last_attended_at, asc: r.name)

  defp scope(q, sort: "attended-"),
    do: order_by(q, [r, last_attended: l], desc_nulls_last: l.last_attended_at, asc: r.name)

  defp sort(q, "standing" <> _ = sort, now) do
    q
    |> order_by(^[asc: dynamic(not (^Member.current_dynamic(now)))])
    |> scope(sort: sort)
  end

  defp sort(q, sort, _now), do: scope(q, sort: sort)
end
