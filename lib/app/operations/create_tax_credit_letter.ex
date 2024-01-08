import Ecto.Query

alias App.Model.Member
alias App.Model.TaxCreditLetter
alias App.Repo
alias Service.Format
alias Service.Random

defmodule App.Operation.CreateTaxCreditLetter do
  def call(team: team, member_id: member_id, year: year) do
    member = Member.get_by(id: member_id, team_id: team.id)
    ref_id = "SRVTC-#{Random.token(5)}"
    letter_content = build_letter_content(team, member, ref_id, year)

    %{
      member_id: member.id,
      ref_id: ref_id,
      year: year,
      letter_content: letter_content
    }
    |> TaxCreditLetter.build_new_changeset()
    |> Repo.insert!()
    |> Repo.preload(:member)
  end

  defp build_letter_content(team, member, ref_id, year) do
    summary = build_hours_summary(member, year)
    certified_at = DateTime.utc_now()
    formatted_certified_on = Format.legal_date(certified_at, team.timezone)

    """
    #{team.mailing_address}


    To whom it may concern:

    Name: #{member.name}
    Address: #{member.address}

    This letter serves to confirm that the above noted individual has completed eligible volunteer search and rescue hours for #{team.name}, an ‘Eligible Search and Rescue Organization recognized by the RCMP’ in the #{year} calendar year.

    Primary Hours: #{summary.primary_hours}
    Secondary Hours: #{summary.secondary_hours}
    Total Hours: #{summary.total_hours}

    Please contact the writer if you have any questions.

    Certified on #{formatted_certified_on}.



    #{team.authorized_by_name || team.name}

    Reference: #{ref_id}
    """
  end

  defp build_hours_summary(member, year) do
    Member
    |> where(id: ^member.id)
    |> Member.include_primary_and_secondary_hours(year)
    |> Repo.one()
  end
end
