alias App.Model.TaxCreditLetter
alias App.Operation.PrintTaxCreditLetter
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
    read = PrintTaxCreditLetter.read(team, letter.member_id, letter.year, now)
    fields = PrintTaxCreditLetter.fields(read, team, TaxCreditLetter.generate_ref_id())

    changeset =
      letter
      |> TaxCreditLetter.build_changeset(fields)
      # The letter page's "Created" matches the date the new text is certified on.
      |> Ecto.Changeset.put_change(:inserted_at, DateTime.add(now, 0, :microsecond))

    # Printed before the transaction, which holds the write lock.
    pdf = changeset |> Ecto.Changeset.apply_changes() |> SaveTaxCreditLetterPDF.draw(read)

    {:ok, letter} =
      Repo.transaction(fn ->
        letter = Repo.update!(changeset)
        SaveTaxCreditLetterPDF.keep!(letter, pdf)
        letter
      end)

    Repo.preload(letter, [member: :team], force: true)
  end
end
