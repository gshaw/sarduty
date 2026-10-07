defmodule App.Mailer.MemberCardMailerTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias App.Mailer.MemberCardMailer
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team

  @google_url "https://pay.google.com/gp/v/save/header.claims.signature"

  defp card do
    team = %Team{name: "Search & Rescue", subdomain: "example"}
    member = %Member{name: "Alex <Example>", email: "alex@example.com", team: team}
    %MemberCard{code: "K7Q4M2XA", member: member}
  end

  test "the Google link is a button in HTML and the bare URL in text" do
    {:ok, _metadata} = MemberCardMailer.deliver(card(), nil, @google_url)

    assert_email_sent(fn email ->
      assert email.text_body =~ "add it to Google Wallet:\n#{@google_url}\n"
      assert email.html_body =~ ~s(<a href="#{@google_url}"><img src=")
      assert email.html_body =~ ~s(/images/add-to-google-wallet.png" alt="Add to Google Wallet")
      assert email.attachments == []
    end)
  end

  test "escapes names in HTML, and leaves out what wasn't given" do
    {:ok, _metadata} = MemberCardMailer.deliver(card(), "pkpass", nil)

    assert_email_sent(fn email ->
      assert email.html_body =~ "<p>Hi Alex &lt;Example&gt;,</p>"
      assert email.html_body =~ "<p>Here is your Search &amp; Rescue ID card.</p>"
      assert email.text_body =~ "Hi Alex <Example>,\n\n"
      assert email.text_body =~ "Apple Wallet"
      refute email.html_body =~ "Google"
      assert [%{filename: "example-id-card.pkpass"}] = email.attachments
    end)
  end
end
