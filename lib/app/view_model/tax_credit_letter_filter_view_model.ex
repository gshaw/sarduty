defmodule App.ViewModel.TaxCreditLetterFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Operation.CountTaxCreditHours
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
      {"None", "none"},
      {"Any", "any"},
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
      |> Attendance.years(team.timezone)
      # Search and Rescue Volunteer Tax Credit (SRVTC) started in 2014
      |> Enum.filter(&(&1 >= 2014))
      |> Enum.map(&Integer.to_string/1)

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

  @doc """
  One record per member: their hours for the year, from `CountTaxCreditHours`, and
  their letter for the year if they have one.
  """
  def find_all(team, filter_options) do
    hours = CountTaxCreditHours.call(team, filter_options.year)

    Member
    |> Member.scope(team_id: team.id)
    |> join(:left, [m], tcl in assoc(m, :tax_credit_letters),
      on: tcl.year == ^filter_options.year
    )
    |> scope(q: filter_options.q)
    |> select([m, tcl], %{
      member: m,
      tax_credit_letter_id: tcl.id,
      tax_credit_letter_ref_id: tcl.ref_id
    })
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, CountTaxCreditHours.get(hours, &1.member.id)))
    |> filter_records(filter_options.filter)
    |> sort_records(filter_options.sort)
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

  defp filter_records(records, "none"), do: Enum.filter(records, &(&1.total_minutes == 0))
  defp filter_records(records, "any"), do: Enum.filter(records, &(&1.total_minutes > 0))

  defp filter_records(records, filter) when is_binary(filter) do
    case Integer.parse(filter) do
      {hours, ""} -> Enum.filter(records, &(&1.total_minutes >= hours * 60))
      _ -> records
    end
  end

  defp filter_records(records, nil), do: records

  # Name breaks ties, so the order holds still between page loads.
  defp sort_records(records, "id"),
    do: Enum.sort_by(records, &{is_nil(&1.member.ref_id), &1.member.ref_id, &1.member.name})

  defp sort_records(records, "name"), do: Enum.sort_by(records, & &1.member.name)
  defp sort_records(records, "primary"), do: sort_desc(records, :primary_minutes)
  defp sort_records(records, "secondary"), do: sort_desc(records, :secondary_minutes)
  defp sort_records(records, _total), do: sort_desc(records, :total_minutes)

  defp sort_desc(records, key), do: Enum.sort_by(records, &{-Map.fetch!(&1, key), &1.member.name})
end
