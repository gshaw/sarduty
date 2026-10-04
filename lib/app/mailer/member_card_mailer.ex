defmodule App.Mailer.MemberCardMailer do
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.MemberCard

  @doc """
  Emails the member their card: the Apple Wallet pass attached, and the Google Wallet
  link as a button, each when given. Expects the card with `member: :team`.
  """
  def deliver(%MemberCard{member: member} = card, pkpass, google_url) do
    team = member.team
    paragraphs = paragraphs(card, pkpass, google_url)

    new()
    |> to({member.name, member.email})
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Your #{team.name} ID card")
    |> text_body(Enum.map_join(paragraphs, "\n\n", &text/1) <> "\n")
    |> html_body(Enum.map_join(paragraphs, "\n", &html/1) <> "\n")
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

  # The body once, as plain strings plus the Google link, so the text and HTML parts
  # can't drift apart.
  defp paragraphs(%MemberCard{member: member} = card, pkpass, google_url) do
    Enum.reject(
      [
        "Hi #{member.name},",
        "Here is your #{member.team.name} ID card.",
        pkpass && "On an iPhone, open the attachment and select Add to put it in Apple Wallet.",
        google_url && {:google, google_url},
        "To verify your ID card, someone scans its QR code with their phone's camera. That opens verify.sarduty.com.",
        "They can also type your code there: #{MemberCard.format_code(card.code)}",
        "Your ID card stops working if you leave the team, or the team replaces or cancels it.",
        "#{member.team.name}, through SAR Duty"
      ],
      &is_nil/1
    )
  end

  defp text({:google, url}),
    do: "On an Android phone, open this link to add it to Google Wallet:\n#{url}"

  defp text(paragraph), do: paragraph

  # Google's own badge, rendered at 2x from its brand assets, since Gmail won't show SVG.
  defp html({:google, url}) do
    src = Web.Endpoint.url() <> "/images/add-to-google-wallet.png"

    """
    <p>On an Android phone, select the button to add it to Google Wallet:</p>
    <p><a href="#{escape(url)}"><img src="#{src}" alt="Add to Google Wallet" width="283" height="50"></a></p>\
    """
  end

  defp html(paragraph), do: "<p>#{escape(paragraph)}</p>"

  defp escape(string), do: string |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
