defmodule App.Operation.EmailTaxCreditLetter do
  alias App.Mailer.TaxCreditLetterMailer
  alias App.Model.TaxCreditLetter

  @doc """
  Emails the letter to its member and returns whether it went, so the page can say so.
  A letter that went is marked sent. Expects `member` preloaded, as
  `TaxCreditLetter.find!/2` and `CreateTaxCreditLetter.call/1` return it.
  """
  def call(%TaxCreditLetter{member: member} = letter) do
    if member.email in [nil, ""] do
      {:error, :no_email}
    else
      case TaxCreditLetterMailer.deliver_tax_credit_letter(letter) do
        {:ok, _metadata} ->
          TaxCreditLetter.set_email_status!(letter, :sent)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
