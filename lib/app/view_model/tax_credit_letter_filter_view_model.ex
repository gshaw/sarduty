defmodule App.ViewModel.TaxCreditLetterFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Repo

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :year, :integer
    field :page, :integer
    field :filter, :string
    field :sort, :string
  end

  def filters,
    do: [
      {"none", "none"},
      {"any", "any"},
      {"50+", "50"},
      {"100+", "100"},
      {"150+", "150"},
      {"200+", "200"}
    ]

  def years(team), do: build_team_year_options(team)

  def current_year, do: Date.utc_today().year |> Integer.to_string()

  defp build_team_year_options(team) do
    current = current_year()

    attendance_years =
      Attendance
      |> join(:inner, [a], m in assoc(a, :member))
      |> where([a, m], m.team_id == ^team.id)
      |> where([a, m], a.status == "attending")
      # Search and Rescue Volunteer Tax Credit (SRVTC) started in 2014
      |> where([a, m], fragment("strftime('%Y', ?) >= '2014'", a.started_at))
      |> select([a, m], fragment("DISTINCT strftime('%Y', ?)", a.started_at))
      |> Repo.all()

    [current | attendance_years]
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  def sort_kinds,
    do: %{
      "ID" => "id",
      "Name" => "name",
      "Primary" => "primary",
      "Secondary" => "secondary",
      "Total" => "total"
    }

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  def find_all(team, filter_options) do
    Member
    |> Member.scope(team_id: team.id)
    |> Member.include_primary_and_secondary_hours(filter_options.year)
    |> scope(q: filter_options.q)
    |> scope(sort: filter_options.sort)
    |> scope(filter: filter_options.filter)
    |> Repo.all()

    # |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  defp build_new do
    %__MODULE__{
      year: Date.utc_today().year - 1,
      filter: "any",
      sort: "total"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :year, :page, :filter, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_inclusion(:filter, filters() |> Enum.map(fn {_label, value} -> value end))
    |> validate_number(:year,
      greater_than_or_equal_to: 2014,
      less_than_or_equal_to: Date.utc_today().year + 1
    )
  end

  defp scope(q, filter: "none"), do: where(q, [r], fragment("total_hours") == 0)
  defp scope(q, filter: "any"), do: where(q, [r], fragment("total_hours") > 0)

  defp scope(q, filter: filter) when is_binary(filter) do
    case Integer.parse(filter) do
      {hours, ""} -> where(q, [r], fragment("total_hours") >= ^hours)
      _ -> q
    end
  end

  defp scope(q, q: nil), do: q
  defp scope(q, q: ""), do: q

  defp scope(q, q: search_filter) do
    # https://dev.to/ivor/beware-ectos-orwhere-pitfall-50bb
    subquery =
      Member
      |> or_where([r], like(r.name, ^"%#{search_filter}%"))
      |> or_where([r], like(r.ref_id, ^"%#{search_filter}%"))
      |> select([:id])

    where(q, [r], r.id in subquery(subquery))
  end

  defp scope(q, sort: "id"), do: order_by(q, [r], asc_nulls_last: r.ref_id)
  defp scope(q, sort: "name"), do: order_by(q, [r], asc: r.name)
  defp scope(q, sort: "primary"), do: order_by(q, [r], desc: fragment("primary_hours"))
  defp scope(q, sort: "secondary"), do: order_by(q, [r], desc: fragment("secondary_hours"))
  defp scope(q, sort: "total"), do: order_by(q, [r], desc: fragment("total_hours"))
end
