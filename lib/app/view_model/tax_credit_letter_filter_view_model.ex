defmodule App.ViewModel.TaxCreditLetterFilterViewModel do
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
    field :cutoff, :integer
    field :sort, :string
  end

  def cutoffs, do: [0, 50, 100, 150, 200]
  def years, do: Range.to_list(2018..Date.utc_today().year)

  def sort_kinds,
    do: %{
      "Name" => "name",
      "ID" => "id",
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

  def fetch_all(team, filter_options) do
    Member
    |> Member.scope(team_id: team.id)
    |> include_primary_and_secondary_hours(filter_options.year)
    |> scope(q: filter_options.q)
    |> scope(sort: filter_options.sort)
    |> scope(cutoff: filter_options.cutoff)
    |> Repo.all()

    # |> Repo.paginate(%{page: filter_options.page, page_size: filter_options.limit})
  end

  defp build_new do
    %__MODULE__{
      year: Date.utc_today().year - 1,
      cutoff: 200,
      sort: "total"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :year, :page, :cutoff, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:year,
      greater_than_or_equal_to: Enum.min(years()),
      less_than_or_equal_to: Enum.max(years())
    )
    |> validate_number(:cutoff,
      greater_than_or_equal_to: Enum.min(cutoffs()),
      less_than_or_equal_to: Enum.max(cutoffs())
    )
  end

  defp scope(q, cutoff: cutoff), do: where(q, [r], fragment("total_hours") >= ^cutoff)

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

  defp scope(q, sort: "name"), do: order_by(q, [r], asc: r.name)
  defp scope(q, sort: "id"), do: order_by(q, [r], asc_nulls_last: r.ref_id)
  defp scope(q, sort: "primary"), do: order_by(q, [r], desc: fragment("primary_hours"))
  defp scope(q, sort: "secondary"), do: order_by(q, [r], desc: fragment("secondary_hours"))
  defp scope(q, sort: "total"), do: order_by(q, [r], desc: fragment("total_hours"))

  defp include_primary_and_secondary_hours(query, year) do
    from(
      m in query,
      left_join: primary in subquery(Activity.tagged_activities_summary(year, ["Primary Hours"])),
      on: m.id == primary.member_id,
      left_join:
        secondary in subquery(Activity.tagged_activities_summary(year, ["Secondary Hours"])),
      on: m.id == secondary.member_id,
      select: %{
        member: m,
        primary_hours: fragment("? as primary_hours", coalesce(primary.hours, 0)),
        secondary_hours: fragment("? as secondary_hours", coalesce(secondary.hours, 0)),
        total_hours:
          fragment(
            "(? + ?) as total_hours",
            coalesce(primary.hours, 0),
            coalesce(secondary.hours, 0)
          )
      }
    )
  end
end
