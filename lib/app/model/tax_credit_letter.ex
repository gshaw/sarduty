defmodule App.Model.TaxCreditLetter do
  use App, :model

  import Ecto.Query

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.TaxCreditLetter
  alias App.Repo

  # The space left to sign in, as CreateTaxCreditLetter writes it.
  @signature_gap "\n\n\n\n\n"

  schema "tax_credit_letters" do
    belongs_to :member, Member
    field :ref_id, :string
    field :year, :integer
    field :letter_content, :string, redact: true
    # The hours the letter says, as it was created. Empty for an old letter whose text
    # did not parse.
    field :primary_minutes, :integer
    field :secondary_minutes, :integer
    # The team's signature PNG when the letter was made. Empty for letters made before
    # #194 or by a team with no signature.
    field :signature, :binary, redact: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%TaxCreditLetter{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :ref_id,
      :member_id,
      :year,
      :letter_content,
      :primary_minutes,
      :secondary_minutes,
      :signature
    ])
    |> validate_required([
      :ref_id,
      :member_id,
      :year,
      :letter_content
    ])
    |> validate_number(:year, greater_than_or_equal_to: 2014, less_than: 2100)
  end

  def find!(team, id) do
    query =
      from(tcl in TaxCreditLetter,
        left_join: m in assoc(tcl, :member),
        where: tcl.id == ^id,
        where: m.team_id == ^team.id,
        preload: [member: :team]
      )

    Repo.one!(query)
  end

  @ref_prefix "SRVTC-"

  @doc """
  A new reference number: `SRVTC-` and 8 random characters from the ID card alphabet,
  `SRVTC-K7Q4M2XA`. It's what someone types to verify the letter, so it can't be guessed.
  Letters before #207 have 5 characters from `Service.Random.token/1`, `SRVTC-M4K11`.
  """
  def generate_ref_id, do: @ref_prefix <> MemberCard.generate_code()

  @doc """
  What someone typed, as a stored reference number: `{:current, ref_id}` for a code
  from `generate_ref_id/0`, `{:old, ref_id}` for one from before #207, nil for neither.
  Case, spaces, dashes, and the `SRVTC` prefix don't matter.
  """
  def parse_ref_id(input) when is_binary(input) do
    code =
      input
      |> String.upcase()
      |> String.replace(~r/[\s-]/, "")
      |> String.replace_prefix("SRVTC", "")

    cond do
      MemberCard.normalize_code(code) -> {:current, @ref_prefix <> code}
      code =~ ~r/^[A-Z1-9]{5}$/ -> {:old, @ref_prefix <> code}
      true -> nil
    end
  end

  def parse_ref_id(_input), do: nil

  @doc "Whether the letter's reference number is one the verify site can show alone."
  def current_ref_id?(%TaxCreditLetter{ref_id: ref_id}),
    do: match?({:current, ^ref_id}, parse_ref_id(ref_id))

  @doc "The letter's page on the verify site, which its QR code opens."
  def verify_url(%TaxCreditLetter{ref_id: ref_id}, verify_url),
    do: "#{verify_url}/letters/#{ref_id}"

  @doc """
  The letter with this reference number, for the verify site. An old reference number
  was never unique or hard to guess, so it also needs the member's last name.
  """
  def find_by_ref_id({:current, ref_id}) do
    TaxCreditLetter
    |> where([l], l.ref_id == ^ref_id)
    |> preload(member: :team)
    |> Repo.one()
  end

  def find_by_ref_id({:old, ref_id}, last_name) do
    TaxCreditLetter
    |> where([l], l.ref_id == ^ref_id)
    |> preload(member: :team)
    |> Repo.all()
    |> Enum.filter(&last_name_matches?(&1.member, last_name))
    |> only_one()
  end

  defp only_one([letter]), do: letter
  defp only_one(_none_or_several), do: nil

  @doc """
  Whether `last_name` is the member's last name, ignoring case. D4H names come as
  "Nadia Mercer" or "Mercer, Nadia".
  """
  def last_name_matches?(member, last_name) do
    want = last_name |> String.trim() |> String.downcase()

    case member.name |> String.downcase() |> String.split(",", parts: 2) do
      _name when want == "" -> false
      [last, _first] -> String.trim(last) == want
      [name] -> String.ends_with?(" " <> String.trim(name), " " <> want)
    end
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
  lines, as `Service.Format.duration_as_hours_minutes_long/1` writes them. Nil when
  either is missing, or is a bare number with no unit.
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
    case Regex.run(~r/^(?:(\d+) hours?)?(?:, )?(?:(\d+) minutes?)?$/, value) do
      [_all, hours] -> {:ok, String.to_integer(hours) * 60}
      [_all, hours, minutes] -> {:ok, to_minutes(hours, minutes)}
      _ -> :error
    end
  end

  defp to_minutes("", minutes), do: String.to_integer(minutes)
  defp to_minutes(hours, minutes), do: String.to_integer(hours) * 60 + String.to_integer(minutes)

  @doc """
  The letter's text split where the signature goes: `{body, signer_block_onward}`, at
  the blank lines between "Certified on" and the signer's name. `:error` for text
  without that gap.
  """
  def split_at_signature(content) do
    case String.split(content, @signature_gap, parts: 2) do
      [body, rest] -> {body, rest}
      [_content] -> :error
    end
  end

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
