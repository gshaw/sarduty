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
      TaxCreditLetter.set_emailed!(letter, now)
      :ok
    end
  end

  @doc """
  `call/2` for a team admin's click, with no job to try again: a refused send marks the
  letter failed at once, so its row and page say Did not send.
  """
  def send_now(%PublishedPDF{} = letter, now \\ DateTime.utc_now()) do
    case call(letter, now) do
      {:error, reason} when reason != :no_email ->
        TaxCreditLetter.set_email_status!(letter, :failed)
        {:error, reason}

      result ->
        result
    end
  end

  defp email?(member), do: if(member.email in [nil, ""], do: {:error, :no_email}, else: :ok)
end
