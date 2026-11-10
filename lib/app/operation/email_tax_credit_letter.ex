defmodule App.Operation.EmailTaxCreditLetter do
  @moduledoc """
  Emails a tax credit letter's published PDF to its member (#918, #970), with the words
  its document's `email to member` writes, and records that it went. A member with no
  email gets none. Expects the letter with its member and team.
  """

  alias App.Mailer.TaxCreditLetterMailer
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.PrintTaxCreditLetter

  @doc "`:ok`, `{:error, :no_email}`, or `{:error, reason}` when the email didn't send."
  def call(%PublishedPDF{member: member} = letter, now \\ DateTime.utc_now()) do
    with :ok <- email?(member),
         email = PrintTaxCreditLetter.email(letter, now),
         attachment = PublishedPDF.attachment(letter),
         {:ok, _metadata} <- TaxCreditLetterMailer.deliver(letter, email, attachment) do
      TaxCreditLetter.set_email_status!(letter, :sent)
      :ok
    end
  end

  defp email?(member), do: if(member.email in [nil, ""], do: {:error, :no_email}, else: :ok)
end
