defmodule App.Mailer.HelpMailerTest do
  use ExUnit.Case, async: true

  alias App.Mailer.HelpMailer
  alias App.Model.Team
  alias App.Operation.SendHelpMessage

  @team %Team{name: "Coast Range SAR"}
  @cameron %{name: "Cameron Ruiz", email: "cameron.ruiz@example.com"}
  @alex %{name: "Alex Chen", email: "alex.chen@example.com"}
  @sam %{name: "Sam Rivera", email: "sam.rivera@example.com"}
  @about %{page: "https://sarduty.com/teams/coastrange/activities/1", device: "iPhone, Safari"}

  test "one email to the contacts and the site admins, with Reply-To and a copy for the sender" do
    to = SendHelpMessage.recipients(["team", "site_admins"], [@alex, @sam])
    email = HelpMailer.build(@team, @cameron, "My hours show 0.", to, @about)

    assert email.to == [
             {"Alex Chen", "alex.chen@example.com"},
             {"Sam Rivera", "sam.rivera@example.com"},
             {"SAR Duty site admins", "support@sarduty.com"}
           ]

    assert email.cc == [{"Cameron Ruiz", "cameron.ruiz@example.com"}]
    assert email.reply_to == {"Cameron Ruiz", "cameron.ruiz@example.com"}
    assert email.subject == "Coast Range SAR: a question from Cameron Ruiz"
    assert email.text_body =~ "My hours show 0.\n\n--\n"
    assert email.text_body =~ "They came from https://sarduty.com/teams/coastrange/activities/1."

    assert email.text_body =~
             "It went to Alex Chen, Sam Rivera, and the SAR Duty site admins. Reply all"

    assert email.text_body =~ "\niPhone, Safari\n"
  end

  test "to the site admins alone, from a member with no name" do
    to = SendHelpMessage.recipients(["site_admins"], [])
    email = HelpMailer.build(@team, %{@cameron | name: nil}, "Hi", to, %{page: nil, device: nil})

    assert email.to == [{"SAR Duty site admins", "support@sarduty.com"}]
    assert email.subject == "Coast Range SAR: a question from cameron.ruiz@example.com"
    refute email.text_body =~ "They came from"
  end

  test "the team alone leaves the site admins off" do
    to = SendHelpMessage.recipients(["team"], [@alex])
    assert HelpMailer.went_to(to) == "Alex Chen"

    assert HelpMailer.build(@team, @cameron, "Hi", to, @about).to == [
             {"Alex Chen", "alex.chen@example.com"}
           ]
  end
end
