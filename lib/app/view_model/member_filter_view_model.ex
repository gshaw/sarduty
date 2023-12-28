defmodule App.ViewModel.MemberFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Activity
  alias App.Model.Member
  alias App.Repo

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :year, :integer
    field :page, :integer
    field :limit, :integer
    field :sort, :string
  end

  def limits, do: [10, 25, 50, 100, 250, 500, 1000]

  def years, do: [2018, 2019, 2020, 2021, 2022, 2023, 2024]

  def sort_kinds,
    do: %{
      "Name" => "name",
      "Role" => "role",
      "ID ↓" => "id:desc",
      "ID ↑" => "id:asc",
      "Joined ↓" => "date:desc",
      "Joined ↑" => "date:asc",
      "Activities ↓" => "count:desc",
      "Activities ↑" => "count:asc",
      "Hours ↓" => "hours:desc",
      "Hours ↑" => "hours:asc"
    }

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
    |> scope(sort: filter_options.sort)
    |> build_activity_summary(filter_options.year)
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  defp build_new do
    %__MODULE__{
      year: 2023,
      limit: 100,
      sort: "name"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :year, :page, :limit, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:year, greater_than_or_equal_to: 2018, less_than_or_equal_to: 2024)
    |> validate_number(:page, greater_than_or_equal_to: 1)
    |> validate_number(:page, greater_than_or_equal_to: 1, less_than_or_equal_to: 1000)
  end

  defp scope(q, q: nil), do: q
  defp scope(q, q: ""), do: q

  defp scope(q, q: search_filter) do
    # https://dev.to/ivor/beware-ectos-orwhere-pitfall-50bb
    subquery =
      Member
      |> where([r], like(r.name, ^"%#{search_filter}%"))
      |> or_where([r], like(r.position, ^"%#{search_filter}%"))
      |> or_where([r], like(r.ref_id, ^"%#{search_filter}%"))
      |> select([:id])

    where(q, [r], r.id in subquery(subquery))
  end

  defp scope(q, sort: "name"), do: order_by(q, [r], asc: r.name)
  defp scope(q, sort: "role"), do: order_by(q, [r], asc_nulls_last: r.position)
  defp scope(q, sort: "id:desc"), do: order_by(q, [r], desc: r.ref_id)
  defp scope(q, sort: "id:asc"), do: order_by(q, [r], asc_nulls_last: r.ref_id)
  defp scope(q, sort: "date:desc"), do: order_by(q, [r], desc: r.joined_at)
  defp scope(q, sort: "date:asc"), do: order_by(q, [r], asc: r.joined_at)
  defp scope(q, sort: "count:desc"), do: order_by(q, [r], desc: fragment("count"))
  defp scope(q, sort: "count:asc"), do: order_by(q, [r], asc: fragment("count"))
  defp scope(q, sort: "hours:desc"), do: order_by(q, [r], desc: fragment("hours"))
  defp scope(q, sort: "hours:asc"), do: order_by(q, [r], asc: fragment("hours"))

  defp build_activity_summary(query, year, tags \\ ["Primary Hours", "Secondary Hours"]) do
    from(
      m in query,
      left_join: summary in subquery(tagged_activities_summary(year, tags)),
      on: m.id == summary.member_id,
      select: %{
        member: m,
        hours: fragment("? as hours", coalesce(summary.hours, 0)),
        count: fragment("? as count", coalesce(summary.count, 0))
      }
    )
  end

  defp tagged_activities_summary(year, tags) do
    tagged_activitity_ids_q =
      Activity
      |> Activity.scope(tags: tags)
      |> select([:id])

    from(
      ac in Activity,
      left_join: at in assoc(ac, :attendances),
      left_join: m in assoc(at, :member),
      where: fragment("strftime('%Y', ?) = ?", at.started_at, ^Integer.to_string(year)),
      where: ac.id in subquery(tagged_activitity_ids_q),
      group_by: m.id,
      select: %{
        member_id: m.id,
        count: count(ac.id),
        hours: sum(at.duration_in_minutes) / 60
      }
    )
  end

  # def build_activity_summary2(query, year \\ 2023) do
  #   from(
  #     m in query,
  #     left_join: pri in subquery(activity_summary(year, "Primary Hours")),
  #     as: :primary,
  #     on: m.id == pri.member_id,
  #     left_join: sec in subquery(activity_summary(year, "Secondary Hours")),
  #     as: :secondary,
  #     on: m.id == sec.member_id,
  #     select: %{
  #       member: m,
  #       primary_hours: fragment("? as primary_hours", coalesce(pri.hours, 0)),
  #       primary_count: fragment("? as primary_count", coalesce(pri.count, 0)),
  #       secondary_hours: fragment("? as secondary_hours", coalesce(sec.hours, 0)),
  #       secondary_count: fragment("? as secondary_count", coalesce(sec.count, 0)),
  #       hours: fragment("? as hours", coalesce(pri.hours, 0) + coalesce(sec.hours, 0))
  #     }
  #   )
  # end

  # def activity_summary(year, tag) do
  #   # year = 2023
  #   # tag = "Primary Hours"
  #   # tag = "Secondary Hours"

  #   # query =
  #   from(
  #     ac in Activity,
  #     left_join: at in assoc(ac, :attendances),
  #     left_join: m in assoc(at, :member),
  #     where: at.status == "attending",
  #     where: fragment("strftime('%Y', ?) = ?", at.started_at, ^Integer.to_string(year)),
  #     where: ^tag in ac.tags,
  #     group_by: m.id,
  #     select: %{
  #       member_id: m.id,
  #       count: count(ac.id),
  #       hours: sum(at.duration_in_minutes) / 60
  #     }
  #   )
  # end
end
