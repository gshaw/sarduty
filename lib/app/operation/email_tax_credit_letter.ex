defmodule App.Operation.EmailTaxCreditLetter do
  alias App.Mailer.TaxCreditLetterMailer
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.SaveTaxCreditLetterPDF

  @doc """
  Emails the letter's saved PDF to its member and returns whether it went, so the page
  can say so. A letter without one is published first: its PDF prints and is saved, as
  making the letter does, or `{:error, :not_printed}` when that fails. A letter that went
  is marked sent. Expects `member` and its team preloaded, as `TaxCreditLetter.find!/2`
  and `CreateTaxCreditLetter.call/1` return it.
  """
  def call(%TaxCreditLetter{member: member} = letter) do
    with :ok <- email?(member),
         {:ok, attachment} <- pdf(letter),
         {:ok, _metadata} <- TaxCreditLetterMailer.deliver_tax_credit_letter(letter, attachment) do
      TaxCreditLetter.set_email_status!(letter, :sent)
      :ok
    end
  end

  defp email?(member), do: if(member.email in [nil, ""], do: {:error, :no_email}, else: :ok)

  defp pdf(letter) do
    case PublishedPDF.letter_attachment(letter) do
      nil -> SaveTaxCreditLetterPDF.publish(letter)
      attachment -> {:ok, attachment}
    end
  end
end
