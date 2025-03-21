defmodule App.Mailer.TaxCreditLetterMailer do
  import Swoosh.Email

  alias App.Mailer
  alias App.Operation.BuildTaxCreditLetterAttachment

  require Logger

  defp deliver_with_attachment(recipient, subject, body, attachment) do
    email =
      new()
      |> to(recipient)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> subject(subject)
      |> text_body(body)
      |> attachment(
        Swoosh.Attachment.new(
          {:data, attachment.content},
          filename: attachment.filename,
          content_type: attachment.content_type
        )
      )

    case Mailer.deliver(email) do
      {:ok, metadata} ->
        Logger.notice("delivered email metadata: #{inspect(metadata)}")

      {:error, reason} ->
        Logger.error("email error: #{inspect(reason)}")
    end
  end

  def deliver_tax_credit_letter(letter) do
    email = letter.member.email
    attachment = BuildTaxCreditLetterAttachment.call(letter)
    subject = attachment.title

    body = """
    Attached is the income tax document you need to claim the SAR Volunteers Tax Credit (SRVTC).

    """

    deliver_with_attachment(email, subject, body, attachment)
  end
end
