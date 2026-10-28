defmodule App.ViewModel.MemberFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Attendance
  alias App.Model.EquipmentItem
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCheckIn
  alias App.Model.Standing
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
    field :items, :string
    field :access, :string
    field :standing, :string
    field :group, :integer
    field :activity_tag, :string
    field :page, :integer
    field :sort, :string
  end

  # "missing": current members with no mobile phone or no email (#205).
  def details_kinds, do: [{"All", "all"}, {"Missing", "missing"}]

  # Whether a member holds any of the team's items (#514): who to ask for equipment back
  # before they retire, and who can retire now.
  def items_kinds, do: [{"Any", "all"}, {"Holds some", "held"}, {"Holds none", "none"}]

  # Whether D4H lets a member log in (#514), for retiring members who still can. Members
  # whose access D4H didn't send are in neither.
  def access_kinds(service),
    do: [{"Any", "all"}, {"Can log in to #{service}", "some"}, {"No access", "none"}]

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
    {"Retiring", "retiring"},
    {"Retired", "retired"},
    {"Not a person", "not_a_person"}
  ]

  # What a member's list offers (#440): every standing but Away, which is team admins'
  # own record and often leave. No Active either: Not retired minus Active would name
  # who is away.
  @member_standings [
    {"Retiring", "retiring"},
    {"Retired", "retired"},
    {"Not a person", "not_a_person"}
  ]

  @doc """
  The Standing filter (#366): Not retired, the default, is every member but the retired,
  and All adds them. Its value stays `"current"`. The attendance check can watch several standings, as
  `"active,away"`; that value gets an option of its own, "Active or away", when it's the
  one shown. A member gets Not retired, Retiring, Retired, Not a person, and All. Retiring
  shows only when the team has a Retiring group (#514).
  """
  def standing_kinds(current, team_admin?, retiring?) do
    combined =
      case standings(current) do
        [_, _ | _] = several -> [{several |> Enum.map(&label/1) |> or_list(), current}]
        _one_or_none -> []
      end

    Enum.concat([
      [{"Not retired", "current"}],
      standings_for(team_admin?, retiring?),
      combined,
      [{"All", "all"}]
    ])
  end

  defp standings_for(team_admin?, retiring?) do
    standings = if team_admin?, do: @standings, else: @member_standings
    if retiring?, do: standings, else: List.keydelete(standings, "retiring", 1)
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

  @doc """
  Checks the list's `params`. A member's (#440) first lose what only team admins' records
  answer: the Attended, Details, and Items filters, the standings `standing_kinds/3` doesn't offer
  them, and the Standing sort. Everything else reads the result, so the list, the
  switch's counts, and the form show members nothing more, whatever the URL says.
  """
  def validate(params, team_admin?) do
    changeset = params |> viewer_params(team_admin?) |> build_new_changeset()

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  defp viewer_params(params, true), do: params

  defp viewer_params(params, false) do
    member_values = nil |> standing_kinds(false, true) |> Enum.map(&elem(&1, 1))

    params
    |> Map.drop(["attended", "details", "items", "access"])
    |> Map.reject(fn
      {"standing", value} -> value not in member_values
      {"sort", value} -> is_binary(value) and String.starts_with?(value, "standing")
      _other -> false
    end)
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
    {:ok, filter_options, _changeset} = validate(params, true)
    team |> filter_query(filter_options, now) |> Repo.count_entries()
  end

  @doc """
  The Standing switch's parts (#469): Not retired first, as the list opens, then each
  standing. No All: Not retired and Retired add up to it. A member's are Not retired,
  Retiring, Retired, and Not a person (#440). Retiring only with a Retiring group (#514).
  """
  def standing_switch(team_admin?, retiring?),
    do: [{"Not retired", "current"} | standings_for(team_admin?, retiring?)]

  @doc """
  Whether the switch has a part for `value`. All, and the attendance check's
  `"active,away"`, don't, so the list shows them as the Standing menu.
  """
  def switch_standing?(value, team_admin?, retiring?),
    do: team_admin? |> standing_switch(retiring?) |> List.keymember?(value, 1)

  @doc """
  How many members each standing in `standing_switch/2` has, before the search and after
  every other filter, keyed by value.
  """
  def standing_counts(team, filter_options, team_admin?, now \\ DateTime.utc_now()) do
    team_admin?
    |> standing_switch(Team.retiring?(team))
    |> Map.new(fn {_label, standing} ->
      options = %{filter_options | q: nil, standing: standing}
      {standing, team |> filter_query(options, now) |> Repo.count_entries()}
    end)
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
    |> scope(items: filter_options.items, team: team)
    |> scope(access: filter_options.access)
    |> scope(group: filter_options.group, team: team)
    |> Standing.join(team, Service.Period.today(now, team.timezone))
    |> scope(standing: filter_options.standing, now: now)
  end

  defp build_new do
    %__MODULE__{
      when: current_year(),
      details: "all",
      attended: "all",
      items: "all",
      access: "all",
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
      :items,
      :access,
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
    |> validate_kind(:items, items_kinds())
    |> validate_kind(:access, access_kinds(nil))
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
      [
        m,
        summary: a,
        last_attended: l,
        away: w,
        retiring: rt,
        last_away: la,
        last_check_in: lc
      ] in query,
      select: %{
        member: m,
        activity_count: fragment("? as activity_count", coalesce(a.activity_count, 0)),
        total_minutes: fragment("? as total_minutes", coalesce(a.total_minutes, 0)),
        last_attended_at: type(l.last_attended_at, :utc_datetime),
        away_until: type(w.away_until, :date),
        retiring?: not is_nil(rt.member_id),
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
    |> where([m], is_nil(m.joined_at) or m.joined_at < ^finish)
    |> where([m], is_nil(m.left_at) or m.left_at >= ^start)
  end

  defp scope(q, details: "missing"),
    do:
      q
      |> Member.current_query(DateTime.utc_now())
      |> Member.counted_query()
      |> Member.missing_details_query()

  defp scope(q, details: _all), do: q

  defp scope(q, attended: nil, team: _team, now: _now), do: q
  defp scope(q, attended: "all", team: _team, now: _now), do: q

  defp scope(q, attended: days, team: team, now: now),
    do: Member.not_seen_query(q, team, String.to_integer(days), now)

  defp scope(q, items: "held", team: team),
    do: where(q, [m], m.id in subquery(EquipmentItem.holder_ids_query(team)))

  defp scope(q, items: "none", team: team),
    do: where(q, [m], m.id not in subquery(EquipmentItem.holder_ids_query(team)))

  defp scope(q, items: _all, team: _team), do: q

  defp scope(q, access: "some"), do: Member.d4h_access_query(q, true)
  defp scope(q, access: "none"), do: Member.d4h_access_query(q, false)
  defp scope(q, access: _all), do: q

  defp scope(q, group: nil, team: _team), do: q

  defp scope(q, group: group_id, team: team),
    do: where(q, [m], m.id in subquery(GroupMember.member_ids_query(team.id, group_id)))

  defp scope(q, standing: "all", now: _now), do: q

  defp scope(q, standing: value, now: now) when value in [nil, "current"],
    do: Member.current_query(q, now)

  defp scope(q, standing: value, now: now) do
    standing = Standing.dynamic(now)
    where(q, ^dynamic(^standing in ^standings(value)))
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

  # Never attended comes first going up: the members furthest from their last activity.
  defp scope(q, sort: "attended"),
    do: order_by(q, [r, last_attended: l], asc_nulls_first: l.last_attended_at, asc: r.name)

  defp scope(q, sort: "attended-"),
    do: order_by(q, [r, last_attended: l], desc_nulls_last: l.last_attended_at, asc: r.name)

  # Members who are not active first, either way: away by the day they are back, soonest
  # first going up, then retiring, then not a person. Active, then retired, last.
  defp sort(q, "standing", now),
    do: order_by(q, ^[asc: standing_rank(now), asc: away_until(), asc: dynamic([m], m.name)])

  defp sort(q, "standing-", now),
    do: order_by(q, ^[asc: standing_rank(now), desc: away_until(), asc: dynamic([m], m.name)])

  defp sort(q, sort, _now), do: scope(q, sort: sort)

  defp standing_rank(now) do
    standing = Standing.dynamic(now)

    dynamic(
      fragment(
        "CASE ? WHEN 'away' THEN 0 WHEN 'retiring' THEN 1 WHEN 'not_a_person' THEN 2 WHEN 'active' THEN 3 ELSE 4 END",
        ^standing
      )
    )
  end

  defp away_until, do: dynamic([away: w], w.away_until)
end
