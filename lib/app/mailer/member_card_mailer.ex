defmodule App.Mailer.MemberCardMailer do
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.MemberCard

  @doc """
  Emails the member their card: the Apple Wallet pass attached, and the Google Wallet
  link in the text, each when given. Expects the card with `member: :team`.
  """
  def deliver(%MemberCard{member: member} = card, pkpass, google_url) do
    team = member.team

    new()
    |> to({member.name, member.email})
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Your #{team.name} ID card")
    |> text_body(body(card, pkpass, google_url))
    |> attach_pass(pkpass, team)
    |> Mailer.deliver()
  end

  defp attach_pass(email, nil, _team), do: email

  defp attach_pass(email, pkpass, team) do
    attachment(
      email,
      Swoosh.Attachment.new({:data, pkpass},
        filename: "#{team.subdomain}-member-card.pkpass",
        content_type: "application/vnd.apple.pkpass"
      )
    )
  end

  defp body(%MemberCard{member: member} = card, pkpass, google_url) do
    """
    Hi #{member.name},

    Here is your #{member.team.name} member ID card.
    #{apple_text(pkpass)}#{google_text(google_url)}
    To check your card, someone scans its QR code with their phone's camera, which opens verify.sarduty.com, or types your code there: #{MemberCard.format_code(card.code)}

    If you leave the team, or the team replaces or cancels the card, it stops checking out.

    #{member.team.name}, through SAR Duty
    """
  end

  defp apple_text(nil), do: ""

  defp apple_text(_pkpass),
    do: "\nOn an iPhone, open the attachment and tap Add to put it in Apple Wallet.\n"

  defp google_text(nil), do: ""

  defp google_text(url),
    do: "\nOn an Android phone, open this link to add it to Google Wallet:\n#{url}\n"
end
