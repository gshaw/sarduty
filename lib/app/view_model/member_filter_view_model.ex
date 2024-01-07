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
  def years, do: Range.to_list(2018..(Date.utc_today().year + 1))

  def sort_kinds,
    do: %{
      "Name" => "name",
      "Role" => "role",
      "ID" => "id",
      "Joined ↑" => "date",
      "Joined ↓" => "date-",
      "Activities ↑" => "count",
      "Activities ↓" => "count-",
      "Hours ↑" => "hours",
      "Hours ↓" => "hours-"
    }

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  def build_paginated_content(team, filter_options, tags) do
    Member
    |> Member.scope(team_id: team.id)
    |> scope(q: filter_options.q)
    |> scope(sort: filter_options.sort)
    |> include_activity_summary(filter_options.year, tags)
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  defp build_new do
    %__MODULE__{
      year: Date.utc_today().year,
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
    |> validate_number(:year,
      greater_than_or_equal_to: Enum.min(years()),
      less_than_or_equal_to: Enum.max(years())
    )
    |> validate_number(:page,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: Enum.max(limits())
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

  defp scope(q, sort: "name"), do: order_by(q, [r], asc: r.name)
  defp scope(q, sort: "role"), do: order_by(q, [r], asc_nulls_last: r.position)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc_nulls_last: r.ref_id)
  defp scope(q, sort: "date-"), do: order_by(q, [r], desc: r.joined_at)
  defp scope(q, sort: "date"), do: order_by(q, [r], asc: r.joined_at)
  defp scope(q, sort: "count-"), do: order_by(q, [r], desc: fragment("count"))
  defp scope(q, sort: "count"), do: order_by(q, [r], asc: fragment("count"))
  defp scope(q, sort: "hours-"), do: order_by(q, [r], desc: fragment("hours"))
  defp scope(q, sort: "hours"), do: order_by(q, [r], asc: fragment("hours"))

  defp include_activity_summary(query, year, tags) do
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

  def tagged_activity_ids(tags) do
    subquery = select(Activity, [:id])
    Enum.reduce(tags, subquery, fn tag, sq -> or_where(sq, [ac], ^tag in ac.tags) end)
  end

  defp tagged_activities_summary(year, tags) do
    from(
      ac in Activity,
      left_join: at in assoc(ac, :attendances),
      left_join: m in assoc(at, :member),
      where: fragment("strftime('%Y', ?) = ?", at.started_at, ^Integer.to_string(year)),
      where: ac.id in subquery(tagged_activity_ids(tags)),
      group_by: m.id,
      select: %{
        member_id: m.id,
        count: count(ac.id),
        # Add 0.5 to simulate CEIL so 1.01 hours gives 2 hours credit
        hours: fragment("cast(round(? + 0.5) as int)", sum(at.duration_in_minutes) / 60.0)
      }
    )
  end
end
