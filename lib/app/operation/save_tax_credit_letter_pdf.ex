defmodule App.Operation.SaveTaxCreditLetterPDF do
  @moduledoc """
  Prints a tax credit letter's PDF and keeps it (#918), so every download and email
  after serves that same file. Making or replacing a letter prints it before the
  write, since Typst takes a while and a transaction holds SQLite's one write lock.
  """

  alias App.Model.SavedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.PrintTaxCreditLetter

  @doc """
  Keeps what `draw/2` gave for the letter, inside the transaction that writes it. A
  letter that couldn't be printed loses any PDF it had, since that one no longer
  matches its text; its download prints it again.
  """
  def keep!(%TaxCreditLetter{} = letter, {:ok, attachment}),
    do: SavedPDF.put_letter!(letter, attachment)

  def keep!(%TaxCreditLetter{} = letter, {:error, _reason}), do: SavedPDF.delete_letter!(letter)

  @doc """
  The letter's PDF, unsaved, for a letter that may not be in the database yet:
  `{:ok, attachment}` or `{:error, reason}` when Typst fails. `read` is
  `PrintTaxCreditLetter.read/4`'s, when the caller has it.
  """
  def draw(%TaxCreditLetter{} = letter, read \\ nil), do: PrintTaxCreditLetter.call(letter, read)
end
