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
    field :page, :integer
    field :limit, :integer
    field :sort, :string
  end

  def activity_kinds, do: ["all", "exercise", "event", "incident"]
  def when_kinds(team), do: ["all", "past", "future" | build_team_year_options(team)]
  def limits, do: [10, 25, 50, 100, 250, 500, 1000]

  defp build_team_year_options(team) do
    Activity
    |> where([a], a.team_id == ^team.id)
    |> select([a], fragment("DISTINCT strftime('%Y', ?)", a.started_at))
    |> Repo.all()
    |> Enum.sort(:desc)
  end

  def sort_kinds,
    do: %{
      "Date ↓" => "date-",
      "Date ↑" => "date",
      "Hours ↓" => "hours-",
      "Hours ↑" => "hours",
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
    |> scope(member: member)
    |> scope(q: filter_options.q)
    |> scope(activity: filter_options.activity)
    |> scope(when: filter_options.when)
    |> scope(sort: filter_options.sort)
    |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  defp build_new do
    %__MODULE__{
      when: "all",
      activity: "all",
      limit: 50,
      sort: "date-"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :activity, :when, :page, :limit, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:activity, activity_kinds())
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:page,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: Enum.max(limits())
    )
  end

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

  defp scope(q, when: "all"), do: q
  defp scope(q, when: "past"), do: where(q, [r], r.started_at <= ^DateTime.utc_now())
  defp scope(q, when: "future"), do: where(q, [r], r.started_at >= ^DateTime.utc_now())

  defp scope(q, when: year) when is_binary(year),
    do: where(q, [r], fragment("strftime('%Y', ?) = ?", r.started_at, ^year))

  defp scope(q, activity: "all"), do: q
  defp scope(q, activity: activity), do: where(q, [r], r.activity_kind == ^activity)

  # defp scope(q, tag: tag), do: where(q, [r], ^tag in r.tags)

  # defp scope(q, year: year),
  #   do: where(q, [r], fragment("strftime('%Y', ?) = ?", r.started_at, ^Integer.to_string(year)))

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
