alias App.Model.Member
alias App.Model.TaxCreditLetter
alias App.Operation.CountTaxCreditHours
alias App.Repo
alias Service.Format

defmodule App.Operation.CreateTaxCreditLetter do
  def call(team: team, member_id: member_id, year: year) do
    member = Member.get_by(id: member_id, team_id: team.id)
    rows = CountTaxCreditHours.load_rows(team, year, [member.id])
    ref_id = TaxCreditLetter.generate_ref_id()

    team
    |> plan(member, rows, year, ref_id, DateTime.utc_now())
    |> TaxCreditLetter.build_new_changeset()
    |> Repo.insert!()
    |> Repo.preload(member: :team)
  end

  @doc """
  The new letter's fields for `member`, from their attendance `rows` as
  `CountTaxCreditHours.count/3` takes them.
  """
  def plan(team, member, rows, year, ref_id, now) do
    hours =
      rows |> CountTaxCreditHours.count(year, team.timezone) |> CountTaxCreditHours.get(member.id)

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
    primary = whole_hours(hours.primary_minutes)
    secondary = whole_hours(hours.secondary_minutes)

    """
    #{team.mailing_address}


    To whom it may concern:

    #{member_lines(member)}

    #{member.name} volunteered with #{team.name} in #{year}. #{team.name} is an eligible search and rescue organization under subsection 118.07(1) of the Income Tax Act.

    Primary Hours: #{Format.duration_as_hours_minutes_long(primary)}
    Secondary Hours: #{Format.duration_as_hours_minutes_long(secondary)}
    Total Hours: #{Format.duration_as_hours_minutes_long(primary + secondary)}

    These hours come from #{team.name}'s attendance records.

    #{contact_line(team)}

    Certified on #{formatted_certified_on}.




    #{signer_block(team)}

    Reference: #{ref_id}
    Verify this letter at verify.sarduty.com/letters
    """
  end

  # Rounded down, so a letter never claims an hour the member didn't reach. The total is
  # the sum of the printed lines, so the letter adds up.
  defp whole_hours(minutes), do: div(minutes, 60) * 60

  defp member_lines(%Member{address: address} = member) when address in [nil, ""],
    do: "Name: #{member.name}"

  defp member_lines(member), do: "Name: #{member.name}\nAddress: #{member.address}"

  defp contact_line(team) do
    if Enum.all?([team.authorized_by_phone, team.authorized_by_email], &(&1 in [nil, ""])),
      do: "If you have questions, contact #{team.name}.",
      else: "If you have questions, contact me using the details below."
  end

  @doc "The signer's name, then their title, phone, and email when the team has them."
  def signer_block(team) do
    [
      team.authorized_by_name || team.name,
      team.authorized_by_title,
      team.authorized_by_phone,
      team.authorized_by_email
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end
end
