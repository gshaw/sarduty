defmodule App.ViewModel.AttendanceFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Repo

  @primary_key false
  embedded_schema do
    field :when, :string
    field :tag, :string
    field :page, :integer
    field :limit, :integer
    field :sort, :string
  end

  def when_kinds(member), do: build_member_year_options(member)

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

  def limits, do: [10, 25, 50, 100, 250, 500, 1000]

  defp activity_primary_hours_tag, do: Activity.primary_hours_tag()
  defp activity_secondary_hours_tag, do: Activity.secondary_hours_tag()

  defp build_member_year_options(member) do
    current = current_year()

    attendance_years =
      Attendance
      |> where([a], a.member_id == ^member.id)
      |> where([a], a.status == "attending")
      |> select([a], fragment("DISTINCT strftime('%Y', ?)", a.started_at))
      |> Repo.all()

    years =
      [current | attendance_years]
      |> Enum.uniq()
      |> Enum.sort(:desc)

    [{"All", "all"} | years]
  end

  def current_year, do: Date.utc_today().year |> Integer.to_string()

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  def build_paginated_content(member, filter_options) do
    Attendance
    |> Attendance.scope(member_id: member.id)
    |> scope(when: filter_options.when)
    |> scope(tag: filter_options.tag)
    |> scope(sort: filter_options.sort)
    |> preload(:activity)
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  def total_duration(member, filter_options) do
    Attendance
    |> Attendance.scope(member_id: member.id)
    |> scope(when: filter_options.when)
    |> scope(tag: filter_options.tag)
    |> select([r], coalesce(sum(r.duration_in_minutes), 0))
    |> Repo.one()
  end

  defp build_new do
    %__MODULE__{
      when: current_year(),
      tag: "all",
      sort: "date-",
      limit: 50
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:when, :tag, :page, :limit, :sort])
    |> validate_inclusion(:tag, Enum.map(tag_kinds(), fn {_, v} -> v end))
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:limit,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: Enum.max(limits())
    )
  end

  defp scope(q, when: "all"), do: q

  defp scope(q, when: year) when is_binary(year),
    do: where(q, [r], fragment("strftime('%Y', ?) = ?", r.started_at, ^year))

  defp scope(q, tag: "all"), do: q

  defp scope(q, tag: "both") do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where(
      [at, ac],
      ^activity_primary_hours_tag() in ac.tags or ^activity_secondary_hours_tag() in ac.tags
    )
  end

  defp scope(q, tag: "primary") do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^activity_primary_hours_tag() in ac.tags)
  end

  defp scope(q, tag: "secondary") do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^activity_secondary_hours_tag() in ac.tags)
  end

  defp scope(q, tag: "other") do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^activity_primary_hours_tag() not in ac.tags)
    |> where([at, ac], ^activity_secondary_hours_tag() not in ac.tags)
  end

  defp scope(q, sort: "date-"), do: order_by(q, [r], desc: r.started_at)
  defp scope(q, sort: "date"), do: order_by(q, [r], asc: r.started_at)
  defp scope(q, sort: "hours-"), do: order_by(q, [r], desc: r.duration_in_minutes)
  defp scope(q, sort: "hours"), do: order_by(q, [r], asc: r.duration_in_minutes)
  defp scope(q, sort: "id-"), do: order_by(q, [r], desc: r.activity_id)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc: r.activity_id)
end
