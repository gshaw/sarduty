defmodule App.ViewModel.TaxCreditLetterFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Field
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.TaxCreditLetter
  alias App.Operation.CountTaxCreditHours
  alias App.Operation.EmailTaxCreditLetters
  alias App.Operation.PrintTaxCreditLetter
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

  @doc """
  The stat switch's parts, each a to-do for the members' letters for the year (#970):
  To email, everyone Email would reach that needs it (#995), then no letter yet, a
  letter not emailed, and a letter out of date, for looking closer. A member can be in
  more than one. Emailed letters show under All.
  """
  def letter_kinds,
    do: [
      {"All", nil},
      {"To email", "to_email"},
      {"No letter", "none"},
      {"Not emailed", "not_emailed"},
      {"Out of date", "changed"}
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
  `CountTaxCreditHours`, and their letter for the year if they have one, with what its
  verify page would show differently today (`TaxCreditLetter.changes/4`): out of date
  when there's a line. Every letter for an open year is read at once
  (`PrintTaxCreditLetter.read_each/4`). `shown/2` applies the letter part and the
  search, so the stat switch can count the parts first.
  """
  def find_all(team, filter_options, now \\ DateTime.utc_now()) do
    year = filter_options.year
    hours = CountTaxCreditHours.call(team, year, nil, now)

    rows =
      Member
      |> Member.scope(team_id: team.id)
      |> join(
        :left,
        [m],
        l in subquery(team.id |> TaxCreditLetter.query() |> TaxCreditLetter.current()),
        on: l.member_id == m.id and l.year == ^year
      )
      |> select([m, l], %{member: m, letter: l})
      |> Repo.all()
      |> Enum.map(fn row -> %{row | letter: if(row.letter && row.letter.id, do: row.letter)} end)
      |> filter_rows(hours, filter_options.filter)

    today = letters_today(team, rows, year, now)

    rows
    |> Enum.map(&build_record(&1, CountTaxCreditHours.get(hours, &1.member.id), today, team, now))
    |> sort_records(filter_options.sort)
  end

  # What each letter shown would print today, by member id: none for a closed year, whose
  # letters never go out of date.
  defp letters_today(team, rows, year, now) do
    if TaxCreditLetter.closed?(year, now, team.timezone) do
      %{}
    else
      ids = for %{letter: %{}, member: member} <- rows, do: member.id

      team
      |> PrintTaxCreditLetter.read_each(ids, year, now)
      |> Map.new(fn {id, read} -> {id, PrintTaxCreditLetter.today(team, read)} end)
    end
  end

  @doc "How many records are in each letter part, keyed as `letter_kinds/0`."
  def letter_counts(records) do
    Map.new(letter_kinds(), fn {_label, kind} ->
      {kind, Enum.count(records, &in_kind?(&1, kind))}
    end)
  end

  @doc "The records in the letter part the filters pick that match the search."
  def shown(records, filter_options) do
    Enum.filter(
      records,
      &(in_kind?(&1, filter_options.letter) and
          (StringHelpers.matches?(&1.member.name, filter_options.q) or
             StringHelpers.matches?(&1.member.ref_id, filter_options.q)))
    )
  end

  defp in_kind?(_record, nil), do: true
  defp in_kind?(record, "none"), do: is_nil(record.tax_credit_letter_id)
  defp in_kind?(record, "changed"), do: record.letter_changes != []
  defp in_kind?(record, "to_email"), do: record.email in [:first, :replace, :failed, :not_emailed]

  defp in_kind?(record, "not_emailed"),
    do: record.letter_email_state in [:not_emailed, :failed, :no_email]

  # What Email does for the member (EmailTaxCreditLetters.what/1) is the To email tile's.
  defp build_record(%{member: member, letter: letter}, hours, today, team, now) do
    changes = changes(letter, today[member.id], team, now)

    record =
      Map.merge(hours, %{
        member: member,
        letter: letter,
        tax_credit_letter_id: letter && letter.id,
        letter_email_state: letter && TaxCreditLetter.email_state(letter, member),
        letter_changes: changes
      })

    Map.put(record, :email, EmailTaxCreditLetters.what(Map.put(record, :changes, changes)))
  end

  defp changes(nil, _today, _team, _now), do: []
  defp changes(_letter, nil, _team, _now), do: []

  defp changes(letter, today, team, now),
    do: TaxCreditLetter.changes(letter, today, now, team.timezone)

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
    |> drop_unknown_sort()
    |> drop_unknown_letter()
    |> validate_inclusion(:filter, filters() |> Enum.map(fn {_label, value} -> value end))
    |> validate_number(:year,
      greater_than_or_equal_to: 2014,
      less_than_or_equal_to: Date.utc_today().year + 1
    )
  end

  # An old link may carry a part that's gone, such as ?letter=made; it gets All.
  defp drop_unknown_letter(changeset) do
    kinds = Enum.map(letter_kinds(), fn {_label, kind} -> kind end)

    if get_change(changeset, :letter) in kinds,
      do: changeset,
      else: delete_change(changeset, :letter)
  end

  # An old link may carry a sort that's gone, such as ?sort=id; it gets the default.
  defp drop_unknown_sort(changeset) do
    if get_change(changeset, :sort) in [nil | Map.values(sort_kinds())],
      do: changeset,
      else: delete_change(changeset, :sort)
  end

  # The Hours filter, before any letter is read.
  defp filter_rows(rows, _hours, nil), do: rows

  defp filter_rows(rows, hours, filter) do
    Enum.filter(rows, &hours_fit?(CountTaxCreditHours.get(hours, &1.member.id), filter))
  end

  defp hours_fit?(hours, "none"), do: hours.total_minutes == 0
  defp hours_fit?(hours, "any"), do: hours.total_minutes > 0

  defp hours_fit?(hours, filter) do
    case Integer.parse(filter) do
      {at_least, ""} -> hours.total_minutes >= at_least * 60
      _other -> true
    end
  end

  # Name breaks ties, so the order holds still between page loads.
  defp sort_records(records, "name"), do: Enum.sort_by(records, & &1.member.name)
  defp sort_records(records, "primary"), do: sort_desc(records, :primary_minutes)
  defp sort_records(records, "secondary"), do: sort_desc(records, :secondary_minutes)
  defp sort_records(records, _total), do: sort_desc(records, :total_minutes)

  defp sort_desc(records, key), do: Enum.sort_by(records, &{-Map.fetch!(&1, key), &1.member.name})
end
