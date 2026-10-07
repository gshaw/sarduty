alias App.Model.ReplacedTaxCreditLetter
alias App.Model.TaxCreditLetter
alias App.Operation.CountTaxCreditHours
alias App.Operation.CreateTaxCreditLetter
alias App.Repo

defmodule App.Operation.ReplaceTaxCreditLetter do
  @doc """
  Rewrites the letter with today's hours and a new reference number. It is not emailed.
  The old reference number keeps verifying with the old hours, since the member may
  have handed that letter in already (#207). Expects the letter from
  `TaxCreditLetter.find!/2`, so it is the team's.
  """
  def call(team, %TaxCreditLetter{} = letter, now \\ DateTime.utc_now()) do
    rows = CountTaxCreditHours.load_rows(team, letter.year, [letter.member_id])
    ref_id = TaxCreditLetter.generate_ref_id()
    fields = CreateTaxCreditLetter.plan(team, letter.member, rows, letter.year, ref_id, now)

    {:ok, letter} =
      Repo.transaction(fn ->
        letter |> ReplacedTaxCreditLetter.from_letter(now) |> Repo.insert!()

        letter
        |> TaxCreditLetter.build_changeset(fields)
        # The letter page's "Created" matches the date the new text is certified on.
        |> Ecto.Changeset.put_change(:inserted_at, DateTime.add(now, 0, :microsecond))
        |> Repo.update!()
      end)

    Repo.preload(letter, [member: :team], force: true)
  end
end
