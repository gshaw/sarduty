alias App.Model.Member
alias App.Model.TaxCreditLetter
alias App.Operation.PrintTaxCreditLetter
alias App.Operation.SaveTaxCreditLetterPDF
alias App.Repo

defmodule App.Operation.CreateTaxCreditLetter do
  @moduledoc """
  Makes a member's tax credit letter for a year from its document,
  priv/documents/tax_credit_letter.txt (#918): its text, the hours it keeps, and its
  published PDF all come from one run of the document's reports.
  """

  def call(team: team, member_id: member_id, year: year),
    do: team |> prepare(member_id, year) |> insert!()

  @doc """
  The new letter with its PDF printed (#918), and nothing written yet: printing takes a
  while, so it happens before `insert!/1` takes the write lock.
  """
  def prepare(team, member_id, year, now \\ DateTime.utc_now()) do
    member = Member.get_by(id: member_id, team_id: team.id)
    read = PrintTaxCreditLetter.read(team, member.id, year, now)

    changeset =
      read
      |> PrintTaxCreditLetter.fields(team)
      |> Map.merge(%{member_id: member.id, year: year})
      |> TaxCreditLetter.build_new_changeset()

    letter =
      changeset
      |> Ecto.Changeset.apply_action!(:insert)
      |> Map.put(:member, %{member | team: team})

    %{changeset: changeset, printed: SaveTaxCreditLetterPDF.draw!(letter, read)}
  end

  @doc "Saves a letter from `prepare/4`, publishing its PDF, and returns it with its member and team."
  def insert!(%{changeset: changeset, printed: printed}) do
    {:ok, letter} =
      Repo.transaction(fn ->
        letter = changeset |> Repo.insert!() |> Repo.preload(member: :team)
        SaveTaxCreditLetterPDF.keep!(letter, printed, nil)
        letter
      end)

    Repo.preload(letter, :pdf)
  end
end
