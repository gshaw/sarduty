defmodule App.Mailer.TaxCreditLetterMailer do
  import Swoosh.Email

  alias App.Mailer

  require Logger

  @doc """
  Emails a letter's published PDF to its member: `email` is `%{subject, body}`, from its
  document's `email to member` (App.Operation.EmailTaxCreditLetter, #970).
  """
  def deliver(letter, %{subject: subject, body: body}, attachment) do
    email =
      new()
      |> Mailer.to_member(letter.member)
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
      |> Mailer.for_team(letter.member.team)

    case Mailer.deliver(email) do
      {:ok, metadata} ->
        Logger.notice("delivered email metadata: #{inspect(metadata)}")
        {:ok, metadata}

      {:error, reason} ->
        Logger.error("email error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
