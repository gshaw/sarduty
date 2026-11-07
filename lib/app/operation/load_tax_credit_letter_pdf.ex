defmodule App.Operation.LoadTaxCreditLetterPDF do
  @moduledoc """
  The tax credit letter's PDF for a download or an email: the one saved when it was
  made (#918). A letter without one, such as a name step 1 of #918 couldn't draw
  (#917), or one whose print failed, is printed and saved now. A print that fails
  raises.
  """

  alias App.Model.LetterPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.PrintTaxCreditLetter

  @doc "Expects the letter's member and team loaded."
  def call(%TaxCreditLetter{} = letter) do
    case LetterPDF.attachment(letter) do
      nil ->
        case PrintTaxCreditLetter.call(letter) do
          {:ok, attachment} ->
            LetterPDF.put!(letter, attachment)
            attachment

          {:error, reason} ->
            raise "Tax credit letter #{letter.id} didn't print: #{reason}"
        end

      attachment ->
        attachment
    end
  end
end
