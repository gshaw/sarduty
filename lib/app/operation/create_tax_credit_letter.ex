alias App.Model.Activity
alias App.Model.Member
alias App.Model.TaxCreditLetter
alias App.Operation.CountTaxCreditHours
alias App.Operation.SaveTaxCreditLetterPDF
alias App.Repo
alias Service.Format

defmodule App.Operation.CreateTaxCreditLetter do
  def call(team: team, member_id: member_id, year: year),
    do: team |> prepare(member_id, year) |> insert!()

  @doc """
  The new letter with its PDF drawn (#918), and nothing written yet: drawing takes a
  while, so it happens before `insert!/1` takes the write lock.
  """
  def prepare(team, member_id, year) do
    member = Member.get_by(id: member_id, team_id: team.id)
    rows = CountTaxCreditHours.load_rows(team, year, [member.id])
    ref_id = TaxCreditLetter.generate_ref_id()

    changeset =
      team
      |> plan(member, rows, year, ref_id, DateTime.utc_now())
      |> TaxCreditLetter.build_new_changeset()

    letter =
      changeset
      |> Ecto.Changeset.apply_action!(:insert)
      |> Map.put(:member, %{member | team: team})

    %{changeset: changeset, pdf: SaveTaxCreditLetterPDF.draw(letter)}
  end

  @doc "Saves a letter from `prepare/3`, with its PDF, and returns it with its member and team."
  def insert!(%{changeset: changeset, pdf: pdf}) do
    {:ok, letter} =
      Repo.transaction(fn ->
        letter = changeset |> Repo.insert!() |> Repo.preload(member: :team)
        SaveTaxCreditLetterPDF.keep!(letter, pdf)
        letter
      end)

    letter
  end

  @doc """
  The new letter's fields for `member`, from their attendance `rows` as
  `CountTaxCreditHours.count/4` takes them.
  """
  def plan(team, member, rows, year, ref_id, now) do
    hours =
      rows
      |> CountTaxCreditHours.count(year, team.timezone, Activity.hours_tags(team))
      |> CountTaxCreditHours.get(member.id)

    %{
      member_id: member.id,
      ref_id: ref_id,
      year: year,
      primary_minutes: hours.primary_minutes,
      secondary_minutes: hours.secondary_minutes,
      signature: team.signature,
      letter_content: build_letter_content(team, member, hours, ref_id, year, now)
    }
  end

  defp build_letter_content(team, member, hours, ref_id, year, now) do
    formatted_certified_on = Format.date_long(now, team.timezone)

    """
    #{team.mailing_address}


    To whom it may concern:

    #{member_lines(member)}

    #{member.name} volunteered with #{team.legal_name} in #{year}. #{team.legal_name} is an eligible search and rescue organization under subsection 118.07(1) of the Income Tax Act.

    Primary Hours: #{Format.duration(hours.primary_minutes)}
    Secondary Hours: #{Format.duration(hours.secondary_minutes)}
    Total Hours: #{Format.duration(hours.total_minutes)}

    These hours come from #{team.legal_name}'s attendance records.

    #{contact_line(team)}

    Certified on #{formatted_certified_on}.




    #{signer_block(team)}

    Reference: #{ref_id}
    Verify this letter at verify.sarduty.com/letters
    """
  end

  defp member_lines(%Member{address: address} = member) when address in [nil, ""],
    do: "Name: #{member.name}"

  defp member_lines(member), do: "Name: #{member.name}\nAddress: #{member.address}"

  defp contact_line(team) do
    if Enum.all?([team.authorized_by_phone, team.authorized_by_email], &(&1 in [nil, ""])),
      do: "If you have questions, contact #{team.legal_name}.",
      else: "If you have questions, contact me using the details below."
  end

  @doc "The signer's name, then their title, phone, and email when the team has them."
  def signer_block(team) do
    [
      team.authorized_by_name || team.legal_name,
      team.authorized_by_title,
      team.authorized_by_phone,
      team.authorized_by_email
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end
end
