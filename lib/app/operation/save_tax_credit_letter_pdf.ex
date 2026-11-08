defmodule App.Operation.SaveTaxCreditLetterPDF do
  @moduledoc """
  Prints a tax credit letter's PDF and keeps it (#918). Making or replacing a letter
  publishes it, and so does emailing one that has none: it prints here once, and every
  download and email after serves that saved file. Printing happens before the write, since Typst takes a
  while and a transaction holds SQLite's one write lock.
  """

  alias App.Model.SavedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.PrintTaxCreditLetter

  @doc "Keeps what `draw!/2` gave as the letter's PDF, inside the transaction that writes it."
  def keep!(%TaxCreditLetter{} = letter, attachment), do: SavedPDF.put_letter!(letter, attachment)

  @doc """
  Prints the saved letter's PDF and keeps it: `{:ok, attachment}`, or `{:error,
  :not_printed}` with nothing saved. For a letter with none, when it's emailed.
  """
  def publish(%TaxCreditLetter{} = letter) do
    case PrintTaxCreditLetter.call(letter) do
      {:ok, attachment} ->
        keep!(letter, attachment)
        {:ok, attachment}

      {:error, _reason} ->
        {:error, :not_printed}
    end
  end

  @doc """
  The letter's PDF, unsaved, for a letter that may not be in the database yet. A print
  that fails raises, so no letter is made or replaced without its PDF. `read` is
  `PrintTaxCreditLetter.read/4`'s, when the caller has it.
  """
  def draw!(%TaxCreditLetter{} = letter, read \\ nil) do
    case PrintTaxCreditLetter.call(letter, read) do
      {:ok, attachment} -> attachment
      {:error, reason} -> raise "Tax credit letter #{letter.ref_id} didn't print: #{reason}"
    end
  end
end
