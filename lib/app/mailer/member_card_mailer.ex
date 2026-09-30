defmodule App.Mailer.MemberCardMailer do
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.MemberCard

  @doc "Emails the member their Apple Wallet pass. Expects the card with `member: :team`."
  def deliver(%MemberCard{member: member} = card, pkpass) do
    team = member.team

    new()
    |> to({member.name, member.email})
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Your #{team.name} ID card")
    |> text_body(body(card))
    |> attachment(
      Swoosh.Attachment.new({:data, pkpass},
        filename: "#{team.subdomain}-member-card.pkpass",
        content_type: "application/vnd.apple.pkpass"
      )
    )
    |> Mailer.deliver()
  end

  defp body(%MemberCard{member: member} = card) do
    """
    Hi #{member.name},

    Here is your #{member.team.name} member ID card. On an iPhone, open the attachment and tap Add to put it in Apple Wallet.

    To check your card, someone opens sarduty.com/verify on their own phone and scans the QR code, or types your code: #{MemberCard.format_code(card.code)}

    If you leave the team, or the team replaces or cancels the card, it stops checking out.

    #{member.team.name}, through SAR Duty
    """
  end
end
