defmodule App.Model.TaxCreditLetter do
  use App, :model

  import Ecto.Query

  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Repo

  schema "tax_credit_letters" do
    belongs_to :member, Member
    # Its current PDF (#970), which holds its ID. One it replaced stays, Replaced.
    has_one :pdf, PublishedPDF, where: [replaced_by_id: nil, withdrawn_at: nil]
    field :year, :integer
    field :letter_content, :string, redact: true
    # The hours the letter says, as it was created. Empty for an old letter whose text
    # did not parse.
    field :primary_minutes, :integer
    field :secondary_minutes, :integer
    # When the member first downloaded it from their own pages. A team admin's download
    # doesn't count.
    field :downloaded_at, :utc_datetime_usec
    # Whether its email went: sending while its job waits, then sent or failed. Empty for
    # a letter never emailed, or one made before #516.
    field :email_status, Ecto.Enum, values: [:sending, :sent, :failed]
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%TaxCreditLetter{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :member_id,
      :year,
      :letter_content,
      :primary_minutes,
      :secondary_minutes
    ])
    |> validate_required([
      :member_id,
      :year,
      :letter_content
    ])
    |> validate_number(:year, greater_than_or_equal_to: 2014, less_than: 2100)
  end

  @doc """
  A letter whose email is waiting for its job, with its member and team, or nil once
  it's sent, failed, or gone.
  """
  def get_sending(id) do
    TaxCreditLetter
    |> where([tcl], tcl.id == ^id and tcl.email_status == :sending)
    |> preload([:pdf, member: :team])
    |> Repo.one()
  end

  @doc "Records how the letter's email went."
  def set_email_status!(%TaxCreditLetter{} = letter, status),
    do: letter |> change(email_status: status) |> Repo.update!()

  def find!(team, id) do
    query =
      from(tcl in TaxCreditLetter,
        left_join: m in assoc(tcl, :member),
        where: tcl.id == ^id,
        where: m.team_id == ^team.id,
        preload: [:pdf, member: :team]
      )

    Repo.one!(query)
  end

  @doc "A letter of this member's, by id, for the member's own page (#156). Raises when not."
  def find_for_member!(%Member{} = member, id) do
    TaxCreditLetter
    |> where([tcl], tcl.id == ^id and tcl.member_id == ^member.id)
    |> preload([:pdf, member: :team])
    |> Repo.one!()
  end

  @doc "Marks the letter downloaded by its member, once; later downloads change nothing."
  def mark_downloaded(%TaxCreditLetter{downloaded_at: nil} = letter, now),
    do: letter |> change(downloaded_at: now) |> Repo.update!()

  def mark_downloaded(%TaxCreditLetter{} = letter, _now), do: letter

  @doc "The member's letters, newest year first."
  def get_all_for_member(%Member{} = member) do
    TaxCreditLetter
    |> where([tcl], tcl.member_id == ^member.id)
    |> order_by([tcl], desc: tcl.year, desc: tcl.inserted_at)
    |> Repo.all()
  end

  @doc """
  The year whose letters go out now: last year. Letters for it, or for the year
  still under way, warn when attendance no longer adds up to their hours (#192).
  """
  def current_year(now, timezone), do: Service.YearRange.year_in(now, timezone) - 1

  @doc """
  How the letter's hours compare with `hours`, today's count from
  `CountTaxCreditHours`:

  - `:unknown`: an old letter with no saved hours.
  - `:same`: they agree.
  - `:changed`: they differ, and the letter is for the current year or later, so it
    may be worth replacing.
  - `:changed_old`: they differ on an older letter. It stays as it is.
  """
  def hours_status(%{primary_minutes: nil}, _hours, _now, _timezone), do: :unknown
  def hours_status(%{secondary_minutes: nil}, _hours, _now, _timezone), do: :unknown

  def hours_status(letter, hours, now, timezone) do
    cond do
      {letter.primary_minutes, letter.secondary_minutes} ==
          {hours.primary_minutes, hours.secondary_minutes} ->
        :same

      letter.year >= current_year(now, timezone) ->
        :changed

      true ->
        :changed_old
    end
  end

  def total_minutes(%{primary_minutes: primary, secondary_minutes: secondary})
      when is_integer(primary) and is_integer(secondary),
      do: primary + secondary

  def total_minutes(_letter), do: nil

  @doc """
  `{primary, secondary}` minutes from a letter's "Primary Hours" and "Secondary Hours"
  lines: "212h 30m", "202 hours", or "45 min" as `Service.Format.duration/1` writes
  them, or "212 hours, 30 minutes" as letters before #260 did. Nil when either is
  missing, or is a bare number with no unit.
  """
  def parse_minutes(content) when is_binary(content) do
    with {:ok, primary} <- parse_line(content, "Primary Hours"),
         {:ok, secondary} <- parse_line(content, "Secondary Hours") do
      {primary, secondary}
    else
      _ -> nil
    end
  end

  def parse_minutes(_content), do: nil

  defp parse_line(content, label) do
    case Regex.run(~r/^#{label}: (.+)$/m, content) do
      [_line, value] -> parse_duration(String.trim(value))
      nil -> :error
    end
  end

  defp parse_duration(value) do
    # "1,204h 30m": drop thousands separators, not the comma in "212 hours, 30 minutes".
    value = String.replace(value, ~r/(?<=\d),(?=\d)/, "")

    case Regex.run(~r/^(\d+)h (\d+)m$|^(\d+) min$/, value) do
      [_all, hours, minutes] -> {:ok, to_minutes(hours, minutes)}
      [_all, "", "", minutes] -> {:ok, String.to_integer(minutes)}
      nil -> parse_long_duration(value)
    end
  end

  defp parse_long_duration(value) do
    case Regex.run(~r/^(?:(\d+) hours?)?(?:, )?(?:(\d+) minutes?)?$/, value) do
      [_all, hours] -> {:ok, String.to_integer(hours) * 60}
      [_all, hours, minutes] -> {:ok, to_minutes(hours, minutes)}
      _ -> :error
    end
  end

  defp to_minutes("", minutes), do: String.to_integer(minutes)
  defp to_minutes(hours, minutes), do: String.to_integer(hours) * 60 + String.to_integer(minutes)

  # def get_all do
  #   TaxCreditLetter
  #   |> order_by([t], desc: t.id)
  #   |> Repo.all()
  # end

  # def get(nil), do: nil
  # def get(id), do: Repo.get(TaxCreditLetter, id)
  # def get!(id), do: Repo.get!(TaxCreditLetter, id)
  # def get_by(params), do: Repo.get_by(TaxCreditLetter, params)

  # def update(%TaxCreditLetter{} = tax_credit_letter, params) do
  #   changeset = TaxCreditLetter.build_changeset(tax_credit_letter, params)
  #   Repo.update(changeset)
  # end

  # def delete(%TaxCreditLetter{} = tax_credit_letter), do: Repo.delete(tax_credit_letter)
end
