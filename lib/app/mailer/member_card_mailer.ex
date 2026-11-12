defmodule App.Mailer.MemberCardMailer do
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.MemberCard

  # A text link styled as a button, inline since Gmail strips classes. Text, not an
  # image, so a mail app that blocks images still shows it. The app's primary colour.
  @button "display:inline-block;padding:10px 16px;border-radius:4px;font-weight:700;" <>
            "text-decoration:none;background:#1d4f91;color:#ffffff;"

  @doc """
  Emails the member a link to their card's page (#952), where they add it to Wallet. No
  pass goes with it: the page builds one when they tap. Expects the card with
  `member: :team`.
  """
  def deliver(%MemberCard{member: member}, url) do
    team = member.team
    paragraphs = paragraphs(member, url)

    new()
    |> Mailer.to_member(member)
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Your #{team.name} ID card")
    |> text_body(Enum.map_join(paragraphs, "\n\n", &text/1) <> "\n")
    |> html_body(Enum.map_join(paragraphs, "\n", &html/1) <> "\n")
    |> Mailer.for_team(team)
    |> Mailer.deliver()
  end

  # The body once, as plain strings plus the button, so the text and HTML parts can't
  # drift apart.
  defp paragraphs(member, url) do
    [
      "Hi #{member.name},",
      "Your #{member.team.name} ID card is ready. It shows you are a current member, with your endorsements.",
      {:button, "Get your ID card", url},
      "#{member.team.name}, through SAR Duty"
    ]
  end

  defp text({:button, label, url}), do: "#{label}:\n#{url}"
  defp text(paragraph), do: paragraph

  defp html({:button, label, url}),
    do: ~s(<p><a href="#{escape(url)}" style="#{@button}">#{escape(label)}</a></p>)

  defp html(paragraph), do: "<p>#{escape(paragraph)}</p>"

  defp escape(string), do: string |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
