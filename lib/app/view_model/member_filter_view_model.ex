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
  alias App.Model.Team
  alias App.Repo
  alias App.ViewData.TeamAttention

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :when, :string
    field :status, :string
    field :details, :string
    field :attended, :string
    field :standing, :string
    field :group, :integer
    field :page, :integer
    field :sort, :string
  end

  def status_kinds, do: [{"All", "all"}, {"Active", "active"}, {"Departed", "departed"}]

  # "missing": current members with no mobile phone or no email (#205).
  def details_kinds, do: [{"All", "all"}, {"Missing", "missing"}]

  # Members not at an activity in this many days (#247): every time frame the team
  # setting offers.
  def attended_kinds,
    do: [
      {"Any time", "all"}
      | Enum.map(Team.not_seen_days(), &{"Not in #{TeamAttention.period(&1)}", "#{&1}"})
    ]

  @standings [{"Active", "active"}, {"Away", "away"}, {"Not a person", "not_a_person"}]

  @doc """
  The Standing filter (#366): Any changes nothing for a team that never uses it. The
  attendance check can watch several standings, as `"active,away"`; that value gets an
  option of its own, "Active or away", when it's the one shown.
  """
  def standing_kinds(current \\ nil) do
    combined =
      case standings(current) do
        [_, _ | _] = several -> [{several |> Enum.map(&label/1) |> or_list(), current}]
        _one_or_none -> []
      end

    [{"Any", "any"} | @standings] ++ combined
  end

  defp label(standing), do: Enum.find_value(@standings, fn {l, v} -> v == standing && l end)

  defp or_list([first | rest]),
    do: Enum.join([first | Enum.map(rest, &String.downcase/1)], " or ")

  defp standings(value) when value in [nil, "", "any"], do: []
  defp standings(value), do: String.split(value, ",")

  def sort_kinds,
    do: %{
      "Name" => "name",
      "Role" => "role",
      "ID" => "id",
      "Joined ↑" => "date",
      "Joined ↓" => "date-",
      "Departed ↑" => "departed",
      "Departed ↓" => "departed-",
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

  @rolling_days [30, 60, 90, 180, 365]

  @doc """
  The Period filter (#367): All, the last 30 to 365 days as `"90d"`, then each year with
  attendance as `"2026"`, so old `when=2026` links still open the same list.
  """
  def when_kinds(team) do
    years =
      Attendance
      |> join(:inner, [a], m in assoc(a, :member))
      |> where([a, m], m.team_id == ^team.id)
      |> where([a], a.status == "attending")
      |> Attendance.years(team.timezone)
      |> Enum.map(&Integer.to_string/1)

    [{"All", "all"}] ++
      Enum.map(@rolling_days, &{"Last #{&1} days", "#{&1}d"}) ++
      Enum.map(years, fn y -> {y, y} end)
  end

  @doc """
  The UTC `{start, finish}` a Period covers, as `Service.YearRange` bounds: start
  inclusive, finish exclusive. A rolling period ends at `now`.
  """
  def period_bounds(period, timezone, now) do
    case Integer.parse(period) do
      {days, "d"} ->
        finish = now |> DateTime.truncate(:second) |> DateTime.to_naive()
        {NaiveDateTime.add(finish, -days, :day), finish}

      {_year, ""} ->
        Service.YearRange.bounds(period, timezone)
    end
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
    |> join_attendance_summary(team, filter_options.when, now)
    |> join_last_attended(team)
    |> join_clock(team, now)
    |> scope(sort: filter_options.sort)
    |> select_member_with_attendance()
  end

  # The members the filters keep, with only the joins a filter reads, so count/3 skips
  # the summary and clock joins that never change which rows match.
  defp filter_query(team, filter_options, now) do
    Member
    |> Member.scope(team_id: team.id)
    |> scope(q: filter_options.q)
    |> scope(when: filter_options.when, timezone: team.timezone, now: now)
    |> scope(status: filter_options.status)
    |> scope(details: filter_options.details)
    |> scope(attended: filter_options.attended, team: team, now: now)
    |> scope(group: filter_options.group, team: team)
    |> join_away(team, now)
    |> scope(standing: filter_options.standing)
  end

  defp build_new do
    %__MODULE__{
      when: current_year(),
      status: "active",
      details: "all",
      attended: "all",
      standing: "any",
      sort: "name"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :when, :status, :details, :attended, :standing, :group, :page, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_kind(:status, status_kinds())
    |> validate_kind(:details, details_kinds())
    |> validate_kind(:attended, attended_kinds())
    |> validate_standing()
    |> validate_format(:when, ~r/\A(all|\d{4}|(30|60|90|180|365)d)\z/)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:page, greater_than_or_equal_to: 1)
  end

  defp validate_standing(changeset) do
    known = Enum.map(@standings, &elem(&1, 1))
    value = get_field(changeset, :standing)

    if value in [nil, "any"] or value |> standings() |> Enum.all?(&(&1 in known)),
      do: changeset,
      else: add_error(changeset, :standing, "is invalid")
  end

  defp or_standing("active", acc),
    do: dynamic([m, away: w], ^acc or (not m.not_a_person and is_nil(w.away_until)))

  defp or_standing("away", acc),
    do: dynamic([m, away: w], ^acc or (not m.not_a_person and not is_nil(w.away_until)))

  defp or_standing("not_a_person", acc), do: dynamic([m], ^acc or m.not_a_person)

  defp validate_kind(changeset, field, kinds),
    do: validate_inclusion(changeset, field, Enum.map(kinds, &elem(&1, 1)))

  defp join_attendance_summary(query, team, period, now) do
    from(
      m in query,
      left_join: a in subquery(build_attendance_summary(team, period, now)),
      as: :summary,
      on: m.id == a.member_id
    )
  end

  defp build_attendance_summary(team, period, now) do
    query =
      from(
        at in Attendance,
        join: m in assoc(at, :member),
        where: m.team_id == ^team.id,
        where: at.status == "attending",
        group_by: at.member_id,
        select: %{
          member_id: at.member_id,
          activity_count: count(at.id),
          total_minutes: sum(at.duration_in_minutes)
        }
      )

    started_in(query, period, team.timezone, now)
  end

  defp started_in(query, period, _timezone, _now) when period in [nil, "all"], do: query

  defp started_in(query, period, timezone, now) do
    {start, finish} = period_bounds(period, timezone, now)

    query
    |> where([at], at.started_at >= type(^start, :naive_datetime))
    |> where([at], at.started_at < type(^finish, :naive_datetime))
  end

  defp join_last_attended(query, team) do
    from(
      m in query,
      left_join: l in subquery(Member.last_attended_query(team)),
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
    {start, finish} = period_bounds(period, timezone, now)

    q
    |> where([m], m.joined_at < type(^finish, :naive_datetime))
    |> where([m], is_nil(m.left_at) or m.left_at >= type(^start, :naive_datetime))
  end

  defp scope(q, status: "all"), do: q
  defp scope(q, status: "active"), do: where(q, [r], is_nil(r.left_at))
  defp scope(q, status: "departed"), do: where(q, [r], not is_nil(r.left_at))

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

  defp scope(q, standing: value) do
    case standings(value) do
      [] -> q
      several -> where(q, ^Enum.reduce(several, false, &or_standing/2))
    end
  end

  defp scope(q, sort: "name"), do: order_by(q, [r], asc: r.name)
  defp scope(q, sort: "role"), do: order_by(q, [r], asc_nulls_last: r.position)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc_nulls_last: r.ref_id)
  defp scope(q, sort: "date-"), do: order_by(q, [r], desc: r.joined_at)
  defp scope(q, sort: "date"), do: order_by(q, [r], asc: r.joined_at)
  defp scope(q, sort: "departed-"), do: order_by(q, [r], desc_nulls_last: r.left_at)
  defp scope(q, sort: "departed"), do: order_by(q, [r], asc_nulls_last: r.left_at)
  defp scope(q, sort: "duration-"), do: order_by(q, [r], desc: fragment("total_minutes"))
  defp scope(q, sort: "duration"), do: order_by(q, [r], asc: fragment("total_minutes"))

  defp scope(q, sort: "activities-"),
    do: order_by(q, [r], desc: fragment("activity_count"), asc: r.name)

  defp scope(q, sort: "activities"),
    do: order_by(q, [r], asc: fragment("activity_count"), asc: r.name)

  # By the day an away member is back, soonest first going up; everyone else after. Not a
  # person wins over an away period, as in the Standing column, so it sorts by no date.
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
end
