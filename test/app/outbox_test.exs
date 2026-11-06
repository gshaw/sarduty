defmodule App.OutboxTest do
  # The Outbox (docs/outbox.md): dev's adapter keeps every email, and Twilio keeps a text
  # it doesn't send.
  use App.DataCase

  import App.DataFixtures

  alias App.Adapter.Outbox
  alias App.Adapter.Twilio
  alias App.Mailer
  alias App.Model.OutboxMessage
  alias Web.Components.EmailPreview

  test "the adapter keeps an email, with its team and attachments" do
    team = team_fixture()

    email =
      [to: {"Cameron Ruiz", "cameron@example.com"}, subject: "Letter", text_body: "Attached"]
      |> Swoosh.Email.new()
      |> Swoosh.Email.attachment(
        Swoosh.Attachment.new({:data, "%PDF"},
          filename: "letter.pdf",
          content_type: "application/pdf"
        )
      )
      |> Mailer.for_team(team)

    assert {:ok, %{id: id}} = Outbox.deliver(email, [])

    assert %OutboxMessage{
             kind: :email,
             to: "Cameron Ruiz <cameron@example.com>",
             subject: "Letter",
             attachments: [%{id: attachment_id, filename: "letter.pdf", data: nil}]
           } = message = OutboxMessage.get(team, id)

    assert %{data: "%PDF", content_type: "application/pdf"} =
             OutboxMessage.get_attachment(message, attachment_id)

    assert [%OutboxMessage{id: ^id}] = OutboxMessage.list(:all)
  end

  test "a text Twilio doesn't send is kept, and an open Outbox hears of it" do
    config = Application.get_env(:sarduty, Twilio)
    Application.put_env(:sarduty, Twilio, Keyword.put(config, :deliver, false))
    on_exit(fn -> Application.put_env(:sarduty, Twilio, config) end)
    Phoenix.PubSub.subscribe(App.PubSub, OutboxMessage.topic())

    assert Twilio.send_sms("+16045551234", "Your SAR Duty login code: 123456", :no_team) == :ok

    assert [%OutboxMessage{kind: :text, to: "+16045551234", body: "Your SAR Duty" <> _}] =
             OutboxMessage.list(:all)

    assert_received {:outbox_message, nil}
  end

  test "a team's message is told on its own topic, not another team's" do
    team = team_fixture()
    other = team_fixture()
    Phoenix.PubSub.subscribe(App.PubSub, OutboxMessage.topic(team.id))
    Phoenix.PubSub.subscribe(App.PubSub, OutboxMessage.topic(other.id))

    OutboxMessage.add_text!("+16045551234", "Your code", team.id)

    assert_received {:outbox_message, team_id} when team_id == team.id
    refute_received {:outbox_message, _team_id}
  end

  test "emptying takes every message" do
    OutboxMessage.add_text!("+16045551234", "One")
    OutboxMessage.add_text!("+16045551234", "Two")
    assert OutboxMessage.delete_all(:all) == 2
    assert OutboxMessage.list(:all) == []
  end

  test "a message's text keeps its links apart" do
    assert EmailPreview.split_links("Reply: https://sarduty.com/r/abc\nThanks") ==
             [
               {:text, "Reply: "},
               {:link, "https://sarduty.com/r/abc"},
               {:text, "\nThanks"}
             ]
  end
end
