defmodule App.ViewModel.ActivityFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Activity
  alias App.Model.ChoreEvent
  alias App.Repo

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :activity, :string
    field :when, :string
    field :status, :string
    field :hours, :string
    field :fields, :string
    field :page, :integer
    field :sort, :string
  end

  # The page's stat switch: D4H's kinds in the order D4H lists them, then chores, SAR
  # Duty's own (#575). All is every activity, chores too.
  def activity_kinds,
    do: [
      {"All", "all"},
      {"Incidents", "incident"},
      {"Exercises", "exercise"},
      {"Events", "event"},
      {"Chores", "chores"}
    ]

  # "draft": attendance can still change in D4H, so a team admin checks it (#205).
  def status_kinds, do: [{"All", "all"}, {"Draft", "draft"}, {"Published", "published"}]

  # "untagged": none of the team's hours tags, so it counts for no hours by mistake (#323).
  def hours_kinds, do: [{"All", "all"}, {"No hours tag", "untagged"}]

  # "missing": a required custom field of the activity's kind is empty (#681).
  def fields_kinds, do: [{"All", "all"}, {"Missing", "missing"}]

  def when_kinds(team),
    do: [
      {"All", "all"},
      {"Current", "current"},
      {"Last 30 days", "recent"},
      {"Past", "past"},
      {"Future", "future"} | build_team_year_options(team)
    ]

  @doc """
  The sort that suits `when`, or nil to keep the sort as it is: oldest first
  for Current and Future, newest first for Last 30 days and Past.
  """
  def sort_for_when("current"), do: "date"
  def sort_for_when("recent"), do: "date-"
  def sort_for_when("future"), do: "date"
  def sort_for_when("past"), do: "date-"
  def sort_for_when(_when), do: nil

  defp build_team_year_options(team) do
    Activity
    |> where([a], a.team_id == ^team.id)
    |> Activity.not_deleted()
    |> Activity.years(team.timezone)
    |> Enum.map(fn year -> {Integer.to_string(year), Integer.to_string(year)} end)
  end

  def sort_kinds,
    do: %{
      "Date ↓" => "date-",
      "Date ↑" => "date",
      "Duration ↓" => "hours-",
      "Duration ↑" => "hours",
      "ID ↓" => "id-",
      "ID ↑" => "id"
    }

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  @doc """
  A page of the team's activities for the filters. `member` limits it to the activities
  that member attended.
  """
  def build_paginated_content(team, member, filter_options) do
    team
    |> filtered(member, filter_options)
    |> scope(q: filter_options.q)
    |> scope(activity: filter_options.activity)
    |> scope(sort: filter_options.sort)
    |> select_merge([chores: c], %{chore_minutes: c.minutes})
    |> Repo.paginate(page: filter_options.page)
  end

  @doc """
  The stat switch's counts: how many activities of each kind the other filters keep,
  before the search, with every activity under "all" and chore activities under "chores".
  """
  def kind_counts(team, member, filter_options) do
    counts =
      team
      |> filtered(member, filter_options)
      |> group_by([r, chores: c], selected_as(:kind))
      |> select([r, chores: c], {
        selected_as(
          fragment(
            "CASE WHEN ? IS NULL THEN ? ELSE 'chores' END",
            c.d4h_activity_id,
            r.activity_kind
          ),
          :kind
        ),
        count(r.id)
      })
      |> Repo.all()
      |> Map.new()

    Map.put(counts, "all", counts |> Map.values() |> Enum.sum())
  end

  # Every filter but the kind and the search.
  defp filtered(team, member, filter_options) do
    Activity
    |> Activity.scope(team_id: team.id)
    |> Activity.not_deleted()
    |> scope(member: member)
    |> join(:left, [r], c in subquery(ChoreEvent.totals(team.id)),
      as: :chores,
      on: c.d4h_activity_id == r.d4h_activity_id
    )
    |> scope(when: filter_options.when, timezone: team.timezone)
    |> scope(status: filter_options.status)
    |> scope(hours: filter_options.hours, team: team)
    |> scope(fields: filter_options.fields)
  end

  defp build_new do
    %__MODULE__{
      when: "all",
      activity: "all",
      status: "all",
      hours: "all",
      fields: "all",
      sort: "date-"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :activity, :when, :status, :hours, :fields, :page, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_option(:activity, activity_kinds())
    |> validate_option(:status, status_kinds())
    |> validate_option(:hours, hours_kinds())
    |> validate_option(:fields, fields_kinds())
    |> validate_format(:when, ~r/\A(all|current|recent|past|future|\d{4})\z/)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:page, greater_than_or_equal_to: 1)
  end

  defp validate_option(changeset, field, options),
    do: validate_inclusion(changeset, field, Enum.map(options, fn {_, v} -> v end))

  defp scope(q, member: nil), do: q

  defp scope(q, member: member) do
    q
    |> join(:left, [r], at in assoc(r, :attendances))
    |> where([r, at], at.member_id == ^member.id)
  end

  defp scope(q, q: nil), do: q
  defp scope(q, q: ""), do: q

  defp scope(q, q: search_filter) do
    # https://dev.to/ivor/beware-ectos-orwhere-pitfall-50bb
    subquery =
      Activity
      |> or_where([r], like(r.title, ^"%#{search_filter}%"))
      |> or_where([r], like(r.ref_id, ^"%#{search_filter}%"))
      |> or_where([r], like(r.tracking_number, ^"%#{search_filter}%"))
      |> or_where([r], like(r.tags, ^"%#{search_filter}%"))
      |> or_where([r], like(r.description, ^"%#{search_filter}%"))
      |> select([:id])

    where(q, [r], r.id in subquery(subquery))
  end

  defp scope(q, when: "all", timezone: _), do: q

  defp scope(q, when: "current", timezone: timezone) do
    {start, finish} = Service.Period.current(DateTime.utc_now(), timezone)
    Activity.overlapping(q, start, finish)
  end

  defp scope(q, when: "recent", timezone: _),
    do: Activity.finished_recently(q, DateTime.utc_now())

  defp scope(q, when: "past", timezone: _), do: where(q, [r], r.started_at <= ^DateTime.utc_now())

  defp scope(q, when: "future", timezone: _),
    do: where(q, [r], r.started_at >= ^DateTime.utc_now())

  defp scope(q, when: year, timezone: timezone) when is_binary(year),
    do: Activity.started_in(q, year, timezone)

  defp scope(q, activity: "all"), do: q
  defp scope(q, activity: "chores"), do: where(q, [chores: c], not is_nil(c.d4h_activity_id))

  defp scope(q, activity: activity),
    do: where(q, [r, chores: c], r.activity_kind == ^activity and is_nil(c.d4h_activity_id))

  defp scope(q, status: "draft"), do: where(q, [r], r.is_published == false)
  defp scope(q, status: "published"), do: where(q, [r], r.is_published == true)
  defp scope(q, status: _all), do: q

  defp scope(q, hours: "untagged", team: team),
    do: Activity.without_hours_tag(q, Activity.hours_tags(team))

  defp scope(q, hours: _all, team: _team), do: q

  defp scope(q, fields: "missing"), do: Activity.missing_required_fields(q)
  defp scope(q, fields: _all), do: q

  # defp scope(q, tag: tag), do: where(q, [r], ^tag in r.tags)

  defp scope(q, sort: "date-"), do: order_by(q, [r], desc: r.started_at)
  defp scope(q, sort: "date"), do: order_by(q, [r], asc: r.started_at)

  # A chore activity lasts no time, so it sorts by its members' total (#575).
  defp scope(q, sort: "hours-"), do: order_by(q, ^[desc: duration_days()])
  defp scope(q, sort: "hours"), do: order_by(q, ^[asc: duration_days()])

  defp scope(q, sort: "id-"), do: order_by(q, [r], desc: r.ref_id)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc: r.ref_id)

  # Kept as JULIANDAY(start) - JULIANDAY(finish), as the sort has always been.
  defp duration_days,
    do:
      dynamic(
        [r, chores: c],
        fragment(
          "COALESCE(? / -1440.0, JULIANDAY(?) - JULIANDAY(?))",
          c.minutes,
          r.started_at,
          r.finished_at
        )
      )
end
