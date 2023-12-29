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
    field :date, :string
    field :page, :integer
    field :limit, :integer
    field :sort, :string
  end

  def activity_kinds, do: ["all", "exercise", "event", "incident"]
  def date_kinds, do: ["all", "past", "future"]
  def limits, do: [10, 25, 50, 100, 250, 500, 1000]

  def sort_kinds,
    do: %{
      "Date ↓" => "date:desc",
      "Date ↑" => "date:asc",
      "ID ↓" => "id:desc",
      "ID ↑" => "id:asc"
    }

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  def build_paginated_content(team, filter_options) do
    Activity
    |> Activity.scope(team_id: team.id)
    |> scope(q: filter_options.q)
    |> scope(activity: filter_options.activity)
    |> scope(date: filter_options.date)
    |> scope(sort: filter_options.sort)
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  defp build_new do
    %__MODULE__{
      date: "past",
      activity: "all",
      limit: 50,
      sort: "date:desc"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :date, :activity, :page, :limit, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:activity, activity_kinds())
    |> validate_inclusion(:date, date_kinds())
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:page, greater_than_or_equal_to: 1)
    |> validate_number(:page, greater_than_or_equal_to: 1, less_than_or_equal_to: 1000)
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

  defp scope(q, date: "all"), do: q
  defp scope(q, date: "past"), do: where(q, [r], r.started_at <= ^DateTime.utc_now())
  defp scope(q, date: "future"), do: where(q, [r], r.started_at >= ^DateTime.utc_now())

  defp scope(q, activity: "all"), do: q
  defp scope(q, activity: activity), do: where(q, [r], r.activity_kind == ^activity)

  defp scope(q, tag: tag), do: where(q, [r], ^tag in r.tags)

  defp scope(q, year: year),
    do: where(q, [r], fragment("strftime('%Y', ?) = ?", r.started_at, ^Integer.to_string(year)))

  defp scope(q, sort: "date:desc"), do: order_by(q, [r], desc: r.started_at)
  defp scope(q, sort: "date:asc"), do: order_by(q, [r], asc: r.started_at)
  defp scope(q, sort: "id:desc"), do: order_by(q, [r], desc: r.ref_id)
  defp scope(q, sort: "id:asc"), do: order_by(q, [r], asc: r.ref_id)
end
