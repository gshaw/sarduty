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
        {:ok, metadata}

      {:error, reason} ->
        Logger.error("email error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def deliver_tax_credit_letter(letter) do
    email = letter.member.email
    attachment = BuildTaxCreditLetterAttachment.call(letter)
    subject = attachment.title

    deliver_with_attachment(email, subject, body(letter), attachment)
  end

  @doc "The email's text: what the letter is for, and who answers questions about it."
  def body(letter) do
    team = letter.member.team

    [
      "Attached is your #{letter.year} tax credit letter from #{team.name}.",
      "Claim the Search and Rescue Volunteers Tax Credit (SRVTC) on line 31240 of your tax return. Keep this letter in case the CRA asks for it.",
      questions_line(team)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  # The signer's email, or their phone when they have no email. Nothing without either.
  defp questions_line(team) do
    name = team.authorized_by_name || team.name

    case Enum.reject([team.authorized_by_email, team.authorized_by_phone], &(&1 in [nil, ""])) do
      [contact | _rest] -> "Questions about your hours? Contact #{name} at #{contact}."
      [] -> nil
    end
  end
end
