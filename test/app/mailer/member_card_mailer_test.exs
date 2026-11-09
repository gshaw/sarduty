defmodule App.Mailer.MemberCardMailerTest do
  # The mailer sends, and the Mailer looks up whether its team is a demo (#857).
  use App.DataCase, async: true

  import App.DataFixtures
  import Swoosh.TestAssertions

  alias App.Mailer.MemberCardMailer
  alias App.Model.Member
  alias App.Model.MemberCard

  @url "https://sarduty.com/cards/token"

  defp card do
    team = team_fixture(%{name: "Search & Rescue", subdomain: "example"})
    member = %Member{name: "Alex <Example>", email: "alex@example.com", team: team}
    %MemberCard{code: "K7Q4M2XA9H", member: member}
  end

  test "one button to the card's page, and no pass" do
    {:ok, _metadata} = MemberCardMailer.deliver(card(), @url)

    assert_email_sent(fn email ->
      assert email.subject == "Your Search & Rescue ID card"
      assert email.html_body =~ ~s(<a href="#{@url}" style=")
      assert email.html_body =~ ">Get your ID card</a>"
      assert email.text_body =~ "Get your ID card:\n#{@url}\n"
      refute email.html_body =~ "Google"
      refute email.text_body =~ "K7Q4"
      assert email.attachments == []
    end)
  end

  test "escapes names in HTML" do
    {:ok, _metadata} = MemberCardMailer.deliver(card(), @url)

    assert_email_sent(fn email ->
      assert email.html_body =~ "<p>Hi Alex &lt;Example&gt;,</p>"
      assert email.html_body =~ "<p>Your Search &amp; Rescue ID card is ready."
      assert email.text_body =~ "Hi Alex <Example>,\n\n"
    end)
  end
end
