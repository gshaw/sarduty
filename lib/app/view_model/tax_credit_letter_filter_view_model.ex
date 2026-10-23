defmodule App.ViewModel.TaxCreditLetterFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.TaxCreditLetter
  alias App.Operation.CountTaxCreditHours
  alias App.Repo
  alias Service.StringHelpers

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :year, :integer
    field :page, :integer
    field :filter, :string
    field :letter, :string
    field :sort, :string
  end

  @doc "The stat switch's parts, which split the members by their letter for the year."
  def letter_kinds,
    do: [
      {"All", nil},
      {"No letter", "none"},
      {"Letter", "made"},
      {"Hours changed", "changed"}
    ]

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

  @doc "The year the list opens on: last year, whose letters members need now."
  def default_year, do: Date.utc_today().year - 1

  defp build_team_year_options(team) do
    current = current_year()

    attendance_years =
      DateTime.utc_now()
      |> Attendance.attended()
      |> where([activity: ac], ac.team_id == ^team.id)
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
  One record per member the year and hours filters keep: their hours for the year, from
  `CountTaxCreditHours`, and their letter for the year if they have one, with how its
  hours compare (`TaxCreditLetter.hours_status/4`). `shown/2` applies the letter part and
  the search, so the stat switch can count the parts first.
  """
  def find_all(team, filter_options, now \\ DateTime.utc_now()) do
    hours = CountTaxCreditHours.call(team, filter_options.year, nil, now)

    Member
    |> Member.scope(team_id: team.id)
    |> join(:left, [m], tcl in assoc(m, :tax_credit_letters),
      on: tcl.year == ^filter_options.year
    )
    |> select([m, tcl], %{member: m, letter: tcl})
    |> Repo.all()
    |> Enum.map(&build_record(&1, CountTaxCreditHours.get(hours, &1.member.id), team, now))
    |> filter_records(filter_options.filter)
    |> sort_records(filter_options.sort)
  end

  @doc "How many records are in each letter part, keyed as `letter_kinds/0`."
  def letter_counts(records) do
    records |> Enum.frequencies_by(&letter_kind/1) |> Map.put(nil, length(records))
  end

  @doc "The records in the letter part the filters pick that match the search."
  def shown(records, filter_options) do
    Enum.filter(
      records,
      &((is_nil(filter_options.letter) or letter_kind(&1) == filter_options.letter) and
          (StringHelpers.matches?(&1.member.name, filter_options.q) or
             StringHelpers.matches?(&1.member.ref_id, filter_options.q)))
    )
  end

  defp letter_kind(%{tax_credit_letter_id: nil}), do: "none"
  defp letter_kind(%{letter_hours_status: :changed}), do: "changed"
  defp letter_kind(_record), do: "made"

  defp build_record(%{member: member, letter: letter}, hours, team, now) do
    hours
    |> Map.put(:member, member)
    |> Map.put(:tax_credit_letter_id, letter && letter.id)
    |> Map.put(:tax_credit_letter_ref_id, letter && letter.ref_id)
    |> Map.put(:letter_minutes, letter && TaxCreditLetter.total_minutes(letter))
    |> Map.put(
      :letter_hours_status,
      letter && TaxCreditLetter.hours_status(letter, hours, now, team.timezone)
    )
  end

  defp build_new do
    %__MODULE__{
      year: default_year(),
      filter: "any",
      sort: "total"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :year, :page, :filter, :letter, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_inclusion(:filter, filters() |> Enum.map(fn {_label, value} -> value end))
    |> validate_inclusion(:letter, letter_kinds() |> Enum.map(fn {_label, value} -> value end))
    |> validate_number(:year,
      greater_than_or_equal_to: 2014,
      less_than_or_equal_to: Date.utc_today().year + 1
    )
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
