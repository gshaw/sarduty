alias App.Model.Member
alias App.Model.TaxCreditLetter
alias App.Operation.CountTaxCreditHours
alias App.Repo
alias Service.Format
alias Service.Random

defmodule App.Operation.CreateTaxCreditLetter do
  def call(team: team, member_id: member_id, year: year) do
    member = Member.get_by(id: member_id, team_id: team.id)
    rows = CountTaxCreditHours.load_rows(team, year, [member.id])
    ref_id = "SRVTC-#{Random.token(5)}"

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
      letter_content: build_letter_content(team, member, hours, ref_id, year, now)
    }
  end

  defp build_letter_content(team, member, hours, ref_id, year, now) do
    formatted_certified_on = Format.date_long(now, team.timezone)

    """
    #{team.mailing_address}


    To whom it may concern:

    Name: #{member.name}
    Address: #{member.address}

    This letter serves to confirm that the above noted individual has completed eligible volunteer search and rescue hours for #{team.name}, an ‘Eligible Search and Rescue Organization recognized by the RCMP’ in the #{year} calendar year.

    Primary Hours: #{Format.duration_as_hours_minutes_long(hours.primary_minutes)}
    Secondary Hours: #{Format.duration_as_hours_minutes_long(hours.secondary_minutes)}
    Total Hours: #{Format.duration_as_hours_minutes_long(hours.total_minutes)}

    Please contact the writer if you have any questions.

    Certified on #{formatted_certified_on}.




    #{signer_block(team)}

    Reference: #{ref_id}
    """
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
