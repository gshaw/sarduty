defmodule App.Operation.LoadTaxCreditLetterPDF do
  @moduledoc """
  The tax credit letter's PDF for a download or an email: the one saved when it was
  made (#918). A letter App.Worker.SaveLetterPDFsWorker hasn't reached yet gets it
  drawn and saved now, the same as the worker would. One that can't be drawn (#917)
  raises, as it always has.
  """

  alias App.Model.LetterPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildTaxCreditLetterAttachment

  @doc "Expects the letter's member and team loaded."
  def call(%TaxCreditLetter{} = letter) do
    case LetterPDF.attachment(letter) do
      nil ->
        attachment = BuildTaxCreditLetterAttachment.call(letter)
        LetterPDF.put!(letter, attachment)
        attachment

      attachment ->
        attachment
    end
  end
end
