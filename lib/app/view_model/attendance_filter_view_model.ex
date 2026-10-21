defmodule App.ViewModel.AttendanceFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Tag
  alias App.Repo
  alias App.ViewData.MemberRecords

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :when, :string
    field :tag, :string
    field :activity_tag, :string
    field :page, :integer
    field :sort, :string
  end

  # The years the member attended in, as the member's own page lists them.
  def when_kinds(member) do
    years = member |> MemberRecords.years(DateTime.utc_now()) |> Enum.map(&Integer.to_string/1)
    [{"All", "all"} | Service.Period.rolling_kinds()] ++ years
  end

  # The team's tags, the same Tag filter as the Members page's.
  def activity_tag_kinds(team), do: team.id |> Tag.titles() |> Enum.map(&{&1, &1})

  def tag_kinds,
    do: [
      {"All", "all"},
      {"Both", "both"},
      {"Primary", "primary"},
      {"Secondary", "secondary"},
      {"Other", "other"}
    ]

  def sort_kinds,
    do: %{
      "Date ↓" => "date-",
      "Date ↑" => "date",
      "Duration ↓" => "hours-",
      "Duration ↑" => "hours",
      "ID ↓" => "id-",
      "ID ↑" => "id"
    }

  def current_year, do: Date.utc_today().year |> Integer.to_string()

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  def build_paginated_content(member, filter_options) do
    member
    |> filtered(filter_options)
    |> scope(sort: filter_options.sort)
    |> preload(:activity)
    |> Repo.paginate(page: filter_options.page)
  end

  def total_duration(member, filter_options) do
    member
    |> filtered(filter_options)
    |> select([r], coalesce(sum(r.duration_in_minutes), 0))
    |> Repo.one()
  end

  # The member's attendance that the search and filters keep.
  defp filtered(member, filter_options) do
    DateTime.utc_now()
    |> Attendance.attended()
    |> where([r], r.member_id == ^member.id)
    |> scope(q: filter_options.q)
    |> scope(when: filter_options.when, timezone: member.team.timezone)
    |> scope(tag: filter_options.tag, hours_tags: Activity.hours_tags(member.team))
    |> Attendance.at_tagged(member.team, filter_options.activity_tag)
  end

  defp build_new do
    %__MODULE__{
      when: current_year(),
      tag: "all",
      sort: "date-"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :when, :tag, :activity_tag, :page, :sort])
    |> Field.truncate(:activity_tag, max_length: 100)
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:tag, Enum.map(tag_kinds(), fn {_, v} -> v end))
    |> App.Validate.Period.call(:when)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:page, greater_than_or_equal_to: 1)
  end

  defp scope(q, q: nil), do: q
  defp scope(q, q: ""), do: q

  # The member's activities whose title, number, or tracking number has the text (#350).
  defp scope(q, q: search) do
    activities =
      from a in Activity,
        where:
          like(a.title, ^"%#{search}%") or like(a.ref_id, ^"%#{search}%") or
            like(a.tracking_number, ^"%#{search}%"),
        select: a.id

    where(q, [at], at.activity_id in subquery(activities))
  end

  defp scope(q, when: "all", timezone: _), do: q

  defp scope(q, when: period, timezone: timezone) when is_binary(period),
    do: Attendance.started_in(q, period, timezone)

  defp scope(q, tag: "all", hours_tags: _), do: q

  defp scope(q, tag: "both", hours_tags: %{primary: primary, secondary: secondary}) do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^primary in ac.tags or ^secondary in ac.tags)
  end

  defp scope(q, tag: "primary", hours_tags: %{primary: primary}) do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^primary in ac.tags)
  end

  defp scope(q, tag: "secondary", hours_tags: %{secondary: secondary}) do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^secondary in ac.tags)
  end

  defp scope(q, tag: "other", hours_tags: %{primary: primary, secondary: secondary}) do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^primary not in ac.tags)
    |> where([at, ac], ^secondary not in ac.tags)
  end

  defp scope(q, sort: "date-"), do: order_by(q, [r], desc: r.started_at)
  defp scope(q, sort: "date"), do: order_by(q, [r], asc: r.started_at)
  defp scope(q, sort: "hours-"), do: order_by(q, [r], desc: r.duration_in_minutes)
  defp scope(q, sort: "hours"), do: order_by(q, [r], asc: r.duration_in_minutes)
  defp scope(q, sort: "id-"), do: order_by(q, [r], desc: r.activity_id)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc: r.activity_id)
end
