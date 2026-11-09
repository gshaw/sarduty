defmodule App.Operation.SaveTaxCreditLetterPDF do
  @moduledoc """
  Prints a tax credit letter's PDF and publishes it (#918, #970). Making or replacing a
  letter publishes it, and so does emailing one that has none: it prints here once, with
  a new ID and its verify code, and every download and email after serves that saved
  file. Printing happens before the write, since Typst takes a while and a transaction
  holds SQLite's one write lock.
  """

  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.PrintTaxCreditLetter

  @doc """
  Publishes what `draw!/3` printed as the letter's PDF, inside the transaction that
  writes the letter. `current_id` is the letter's current PDF's id, nil for a new
  letter: the old one becomes Replaced.
  """
  def keep!(%TaxCreditLetter{} = letter, printed, current_id) do
    attrs = %{
      team_id: letter.member.team_id,
      name: printed.name,
      subject: PublishedPDF.letter_subject(letter.member_id, letter.year),
      code: printed.code,
      tax_credit_letter_id: letter.id,
      member_id: letter.member_id,
      year: letter.year
    }

    case PublishedPDF.publish(attrs, printed, current_id) do
      {:ok, pdf} -> pdf
      {:error, :stale} -> raise "Tax credit letter #{letter.id} was published again meanwhile"
    end
  end

  @doc """
  Prints the saved letter's PDF and publishes it: `{:ok, attachment}`, or `{:error,
  :not_printed}` with nothing saved. For a letter with none, when it's emailed.
  """
  def publish(%TaxCreditLetter{} = letter) do
    case PrintTaxCreditLetter.call(letter, PublishedPDF.generate_code()) do
      {:ok, printed} ->
        keep!(letter, printed, nil)
        {:ok, printed.attachment}

      {:error, _reason} ->
        {:error, :not_printed}
    end
  end

  @doc """
  The letter's PDF with a new ID, unsaved, for a letter that may not be in the database
  yet: `%{attachment, keep, shows, name, code}`. A print that fails raises, so no letter
  is made or replaced without its PDF. `read` is `PrintTaxCreditLetter.read/4`'s.
  """
  def draw!(%TaxCreditLetter{} = letter, read) do
    case PrintTaxCreditLetter.call(letter, PublishedPDF.generate_code(), read) do
      {:ok, printed} -> printed
      {:error, reason} -> raise "Tax credit letter for #{letter.year} didn't print: #{reason}"
    end
  end
end
