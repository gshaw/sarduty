alias App.Model.PublishedPDF
alias App.Model.TaxCreditLetter
alias App.Operation.PrintTaxCreditLetter
alias App.Operation.SaveTaxCreditLetterPDF
alias App.Repo

defmodule App.Operation.ReplaceTaxCreditLetter do
  @doc """
  Rewrites the letter with today's hours and publishes its new PDF with a new ID (#918,
  #970). It is not emailed. The old PDF stays, and its verify page says Replaced.
  Expects the letter from `TaxCreditLetter.find!/2`, so it is the team's.
  """
  def call(team, %TaxCreditLetter{} = letter, now \\ DateTime.utc_now()) do
    read = PrintTaxCreditLetter.read(team, letter.member_id, letter.year, now)
    fields = PrintTaxCreditLetter.fields(read, team)
    current = PublishedPDF.current_for_letter(letter)

    changeset =
      letter
      |> TaxCreditLetter.build_changeset(fields)
      # The letter page's "Created" matches the date the new text is certified on.
      |> Ecto.Changeset.put_change(:inserted_at, DateTime.add(now, 0, :microsecond))

    # Printed before the transaction, which holds the write lock.
    printed = changeset |> Ecto.Changeset.apply_changes() |> SaveTaxCreditLetterPDF.draw!(read)

    {:ok, letter} =
      Repo.transaction(fn ->
        letter = Repo.update!(changeset)
        SaveTaxCreditLetterPDF.keep!(letter, printed, current && current.id)
        letter
      end)

    Repo.preload(letter, [:pdf, member: :team], force: true)
  end
end
