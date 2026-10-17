defmodule App.ViewModel.ActivityFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Activity
  alias App.Repo

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :activity, :string
    field :when, :string
    field :status, :string
    field :hours, :string
    field :page, :integer
    field :sort, :string
  end

  def activity_kinds,
    do: [{"All", "all"}, {"Exercise", "exercise"}, {"Event", "event"}, {"Incident", "incident"}]

  # "draft": attendance can still change in D4H, so a team admin checks it (#205).
  def status_kinds, do: [{"All", "all"}, {"Draft", "draft"}, {"Published", "published"}]

  # "untagged": none of the team's hours tags, so it counts for no hours by mistake (#323).
  def hours_kinds, do: [{"All", "all"}, {"No hours tag", "untagged"}]

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

  def build_paginated_content(team, member, filter_options) do
    Activity
    |> Activity.scope(team_id: team.id)
    |> Activity.not_deleted()
    |> scope(member: member)
    |> scope(q: filter_options.q)
    |> scope(activity: filter_options.activity)
    |> scope(when: filter_options.when, timezone: team.timezone)
    |> scope(status: filter_options.status)
    |> scope(hours: filter_options.hours, team: team)
    |> scope(sort: filter_options.sort)
    |> Repo.paginate(page: filter_options.page)
  end

  defp build_new do
    %__MODULE__{
      when: "all",
      activity: "all",
      status: "all",
      hours: "all",
      sort: "date-"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :activity, :when, :status, :hours, :page, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_option(:activity, activity_kinds())
    |> validate_option(:status, status_kinds())
    |> validate_option(:hours, hours_kinds())
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
  defp scope(q, activity: activity), do: where(q, [r], r.activity_kind == ^activity)

  defp scope(q, status: "draft"), do: where(q, [r], r.is_published == false)
  defp scope(q, status: "published"), do: where(q, [r], r.is_published == true)
  defp scope(q, status: _all), do: q

  defp scope(q, hours: "untagged", team: team),
    do: Activity.without_hours_tag(q, Activity.hours_tags(team))

  defp scope(q, hours: _all, team: _team), do: q

  # defp scope(q, tag: tag), do: where(q, [r], ^tag in r.tags)

  defp scope(q, sort: "date-"), do: order_by(q, [r], desc: r.started_at)
  defp scope(q, sort: "date"), do: order_by(q, [r], asc: r.started_at)

  defp scope(q, sort: "hours-"),
    do:
      order_by(q, [r], desc: fragment("JULIANDAY(?) - JULIANDAY(?)", r.started_at, r.finished_at))

  defp scope(q, sort: "hours"),
    do:
      order_by(q, [r], asc: fragment("JULIANDAY(?) - JULIANDAY(?)", r.started_at, r.finished_at))

  defp scope(q, sort: "id-"), do: order_by(q, [r], desc: r.ref_id)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc: r.ref_id)
end
