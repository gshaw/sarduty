defmodule App.ViewModel.MemberFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Member
  alias App.Repo

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :page, :integer
    field :limit, :integer
    field :sort, :string
  end

  def limits, do: [10, 25, 50, 100, 250, 500, 1000]

  def sort_kinds,
    do: %{
      "Name" => "name",
      "Role" => "role",
      "ID" => "id",
      "Joined ↑" => "date",
      "Joined ↓" => "date-"
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
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  defp build_new do
    %__MODULE__{
      limit: 500,
      sort: "name"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :page, :limit, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
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
end
