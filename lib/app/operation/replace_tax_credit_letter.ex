alias App.Model.TaxCreditLetter
alias App.Operation.CountTaxCreditHours
alias App.Operation.CreateTaxCreditLetter
alias App.Operation.SaveTaxCreditLetterPDF
alias App.Repo

defmodule App.Operation.ReplaceTaxCreditLetter do
  @doc """
  Rewrites the letter with today's hours and a new reference number, and saves its new
  PDF in place of the old one (#918). It is not emailed. The old reference number stops
  verifying: only the current letter does. Expects the letter from
  `TaxCreditLetter.find!/2`, so it is the team's.
  """
  def call(team, %TaxCreditLetter{} = letter, now \\ DateTime.utc_now()) do
    rows = CountTaxCreditHours.load_rows(team, letter.year, [letter.member_id])
    ref_id = TaxCreditLetter.generate_ref_id()
    fields = CreateTaxCreditLetter.plan(team, letter.member, rows, letter.year, ref_id, now)

    changeset =
      letter
      |> TaxCreditLetter.build_changeset(fields)
      # The letter page's "Created" matches the date the new text is certified on.
      |> Ecto.Changeset.put_change(:inserted_at, DateTime.add(now, 0, :microsecond))

    # Drawn before the transaction, which holds the write lock.
    pdf = changeset |> Ecto.Changeset.apply_changes() |> SaveTaxCreditLetterPDF.draw()

    {:ok, letter} =
      Repo.transaction(fn ->
        letter = Repo.update!(changeset)
        SaveTaxCreditLetterPDF.keep!(letter, pdf)
        letter
      end)

    Repo.preload(letter, [member: :team], force: true)
  end
end
