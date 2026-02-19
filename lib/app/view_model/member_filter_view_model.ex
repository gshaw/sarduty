defmodule App.ViewModel.MemberFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Repo

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :when, :string
    field :status, :string
    field :page, :integer
    field :limit, :integer
    field :sort, :string
  end

  def limits, do: [10, 25, 50, 100, 250, 500, 1000]

  def status_kinds, do: [{"All", "all"}, {"Active", "active"}, {"Departed", "departed"}]

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
      "Duration ↑" => "duration"
    }

  def when_kinds(team) do
    years =
      Attendance
      |> join(:inner, [a], m in assoc(a, :member))
      |> where([a, m], m.team_id == ^team.id)
      |> where([a], a.status == "attending")
      |> select([a], fragment("DISTINCT strftime('%Y', ?)", a.started_at))
      |> Repo.all()
      |> Enum.sort(:desc)

    [{"All", "all"} | Enum.map(years, fn y -> {y, y} end)]
  end

  def current_year, do: Date.utc_today().year |> Integer.to_string()

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  def build_paginated_content(team, filter_options) do
    Member
    |> Member.scope(team_id: team.id)
    |> scope(q: filter_options.q)
    |> scope(when: filter_options.when)
    |> scope(status: filter_options.status)
    |> join_attendance_summary(filter_options.when)
    |> scope(sort: filter_options.sort)
    |> select_member_with_attendance()
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  defp build_new do
    %__MODULE__{
      when: current_year(),
      status: "active",
      limit: 500,
      sort: "name"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :when, :status, :page, :limit, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:status, Enum.map(status_kinds(), fn {_, v} -> v end))
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:page,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: Enum.max(limits())
    )
  end

  defp join_attendance_summary(query, year) do
    from(
      m in query,
      left_join: a in subquery(build_attendance_summary(year)),
      on: m.id == a.member_id
    )
  end

  defp build_attendance_summary(year) when year in [nil, "all"] do
    from(
      at in Attendance,
      where: at.status == "attending",
      group_by: at.member_id,
      select: %{
        member_id: at.member_id,
        activity_count: count(at.id),
        total_minutes: sum(at.duration_in_minutes)
      }
    )
  end

  defp build_attendance_summary(year) do
    from(
      at in Attendance,
      where: at.status == "attending",
      where: fragment("strftime('%Y', ?) = ?", at.started_at, ^year),
      group_by: at.member_id,
      select: %{
        member_id: at.member_id,
        activity_count: count(at.id),
        total_minutes: sum(at.duration_in_minutes)
      }
    )
  end

  defp select_member_with_attendance(query) do
    from(
      [m, a] in query,
      select: %{
        member: m,
        activity_count: coalesce(a.activity_count, 0),
        total_minutes: fragment("? as total_minutes", coalesce(a.total_minutes, 0))
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

  defp scope(q, when: "all"), do: q
  defp scope(q, when: nil), do: q

  defp scope(q, when: year) when is_binary(year) do
    q
    |> where([m], fragment("strftime('%Y', ?) <= ?", m.joined_at, ^year))
    |> where([m], is_nil(m.left_at) or fragment("strftime('%Y', ?) >= ?", m.left_at, ^year))
  end

  defp scope(q, status: "all"), do: q
  defp scope(q, status: "active"), do: where(q, [r], is_nil(r.left_at))
  defp scope(q, status: "departed"), do: where(q, [r], not is_nil(r.left_at))

  defp scope(q, sort: "name"), do: order_by(q, [r], asc: r.name)
  defp scope(q, sort: "role"), do: order_by(q, [r], asc_nulls_last: r.position)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc_nulls_last: r.ref_id)
  defp scope(q, sort: "date-"), do: order_by(q, [r], desc: r.joined_at)
  defp scope(q, sort: "date"), do: order_by(q, [r], asc: r.joined_at)
  defp scope(q, sort: "departed-"), do: order_by(q, [r], desc_nulls_last: r.left_at)
  defp scope(q, sort: "departed"), do: order_by(q, [r], asc_nulls_last: r.left_at)
  defp scope(q, sort: "duration-"), do: order_by(q, [r], desc: fragment("total_minutes"))
  defp scope(q, sort: "duration"), do: order_by(q, [r], asc: fragment("total_minutes"))
end
