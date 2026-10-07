alias App.Model.TaxCreditLetter
alias App.Operation.CountTaxCreditHours
alias App.Operation.CreateTaxCreditLetter
alias App.Repo

defmodule App.Operation.ReplaceTaxCreditLetter do
  @doc """
  Rewrites the letter with today's hours, keeping its reference number (#192). It is
  not emailed. Expects the letter from `TaxCreditLetter.find!/2`, so it is the team's.
  """
  def call(team, %TaxCreditLetter{} = letter, now \\ DateTime.utc_now()) do
    rows = CountTaxCreditHours.load_rows(team, letter.year, [letter.member_id])

    fields =
      CreateTaxCreditLetter.plan(team, letter.member, rows, letter.year, letter.ref_id, now)

    letter
    |> TaxCreditLetter.build_changeset(fields)
    # The letter page's "Created" matches the date the new text is certified on.
    |> Ecto.Changeset.put_change(:inserted_at, DateTime.add(now, 0, :microsecond))
    |> Repo.update!()
    |> Repo.preload([member: :team], force: true)
  end
end
