# cspell:ignore Łukasz Nowak -- a Polish name, past WinAnsi (#917)
defmodule App.Operation.SaveTaxCreditLetterPDF do
  @moduledoc """
  Draws a tax credit letter's PDF and keeps it (#918), so every download and email
  after serves that same file. Making or replacing a letter draws it before the write,
  since drawing takes a while and a transaction holds SQLite's one write lock.

  A letter with a character WinAnsi can't hold, such as the Ł in Łukasz (#917), can't
  be drawn yet. It's made and verifies as before, with no saved PDF, and its download
  and email fail as they always have, until letters print with Typst.
  """

  alias App.Model.LetterPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildTaxCreditLetterAttachment
  alias Service.PDFLetter

  @doc "Draws the letter's PDF and saves it. `{:ok, attachment}`, or `draw/1`'s error."
  def call(%TaxCreditLetter{} = letter) do
    with {:ok, attachment} <- draw(letter) do
      LetterPDF.put!(letter, attachment)
      {:ok, attachment}
    end
  end

  @doc """
  Keeps what `draw/1` gave for the letter, inside the transaction that writes it. A
  letter that couldn't be drawn loses any PDF it had, since that one no longer
  matches its text.
  """
  def keep!(%TaxCreditLetter{} = letter, {:ok, attachment}),
    do: LetterPDF.put!(letter, attachment)

  def keep!(%TaxCreditLetter{} = letter, {:error, _reason}), do: LetterPDF.delete!(letter)

  @doc """
  The letter's PDF, unsaved, for a letter that may not be in the database yet.
  `{:error, :not_win_ansi}` when the `pdf` package can't write its text (#917).
  """
  def draw(%TaxCreditLetter{} = letter) do
    if PDFLetter.writable?(letter.letter_content),
      do: {:ok, BuildTaxCreditLetterAttachment.call(letter)},
      else: {:error, :not_win_ansi}
  end
end
