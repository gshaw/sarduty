defmodule App.DemoTeamSendsTest do
  # What a Try a demo team sends (#857): nothing. Its email goes to its Outbox, one per
  # member as on a real team, and it never texts. Real teams are untouched.
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures
  import Swoosh.Email, except: [from: 2]
  import Swoosh.TestAssertions

  alias App.Accounts
  alias App.Mailer
  alias App.Model.Member
  alias App.Model.OutboxMessage
  alias App.Model.Reminder
  alias App.Model.TaxCreditLetter
  alias App.Operation.BuildApplePass
  alias App.Operation.ChangeOwnPhone
  alias App.Operation.CreateTaxCreditLetters
  alias App.Operation.SendReminders
  alias Service.PDFLetter

  defp email(team, to) do
    new()
    |> to(to)
    |> Swoosh.Email.from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Will you be there? Training night")
    |> text_body("Body")
    |> html_body("<p>Body</p>")
    |> Mailer.for_team(team)
  end

  describe "App.Mailer" do
    test "keeps a demo team's email in its Outbox" do
      team = team_fixture()
      demo_team_fixture(team)

      assert {:ok, %{id: id}} =
               team
               |> email([{"Cameron Ruiz", "cameron@example.com"}, "avery@example.com"])
               |> Mailer.deliver()

      refute_email_sent()

      assert %OutboxMessage{
               kind: :email,
               to: "Cameron Ruiz <cameron@example.com>, avery@example.com",
               subject: "Will you be there? Training night",
               body: "Body",
               html_body: "<p>Body</p>"
             } = OutboxMessage.get(team, id)
    end

    test "sends a real team's email" do
      team = team_fixture()
      {:ok, _sent} = team |> email({"Cameron Ruiz", "cameron@example.com"}) |> Mailer.deliver()

      assert_email_sent(subject: "Will you be there? Training night")
      assert OutboxMessage.count(team) == 0
    end

    test "sends an email marked for no team" do
      new()
      |> to("cameron@example.com")
      |> Swoosh.Email.from({"SAR Duty", "noreply@sarduty.com"})
      |> subject("Your SAR Duty login code: 123456")
      |> Mailer.for_no_team()
      |> Mailer.deliver()

      assert_email_sent(subject: "Your SAR Duty login code: 123456")
    end

    test "refuses an email with no mark, so none can skip a demo's Outbox" do
      email =
        new()
        |> to("cameron@example.com")
        |> Swoosh.Email.from({"SAR Duty", "noreply@sarduty.com"})
        |> subject("Will you be there? Training night")

      assert_raise ArgumentError, ~r/no team mark/, fn -> Mailer.deliver(email) end
      refute_email_sent()
    end
  end

  describe "sends" do
    setup do
      %{user: user, team: team} = user_with_team_fixture()
      demo_team_fixture(team, %{user_id: user.id})
      starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
      activity = activity_fixture(team, %{title: "Training night", started_at: starts})

      members =
        for name <- ["Avery Chen", "Blake Morrison", "Cameron Ruiz"] do
          member = member_fixture(team, %{name: name})
          attendance_fixture(activity, member, %{status: "requested"})
          member
        end

      %{user: user, team: team, activity: activity, members: members}
    end

    test "reminders to 3 members are 3 emails in the Outbox, all sent", ctx do
      ids = Enum.map(ctx.members, & &1.id)

      assert {:ok, reminders} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, ids, nil, DateTime.utc_now())

      assert Enum.all?(reminders, &(Repo.reload!(&1).status == :sent))
      assert Repo.aggregate(Reminder, :count) == 3
      refute_email_sent()

      messages = OutboxMessage.list(ctx.team)
      assert length(messages) == 3
      assert Enum.all?(messages, &(&1.subject =~ "Training night"))
      assert Enum.any?(messages, &(&1.to =~ "Avery Chen"))
    end

    test "tax credit letters for 3 members are 3 emails in the Outbox, with the PDF", ctx do
      ids = Enum.map(ctx.members, & &1.id)
      summary = CreateTaxCreditLetters.call(ctx.team, 2025, ids)

      assert summary.created == 3 and summary.emailing == 3
      assert Repo.aggregate(TaxCreditLetter, :count) == 3
      refute_email_sent()

      assert [message | _rest] = OutboxMessage.list(ctx.team)
      assert message.subject =~ ~r/^2025 SRVTC/
      assert message.attachments =~ ".pdf"
    end
  end

  describe "texts" do
    test "text login never texts a number on a demo team" do
      text_login_fixture()
      team = team_fixture()
      manager_fixture(team, %{email: "pat@example.com", phone: "604-555-1234"})
      demo_team_fixture(team)

      assert Accounts.text_login_email("+16045551234") == nil
      :ok = Accounts.deliver_login_text("+16045551234")
      refute_received {:text, _, _}
    end

    test "a demo team's phone code goes to its Outbox, not the number" do
      %{user: user, team: team} = user_with_team_fixture()
      demo_team_fixture(team)
      member = Repo.get_by!(Member, team_id: team.id, email: user.email)

      assert {:ok, "+16045550199"} = ChangeOwnPhone.request(member, user, "604-555-0199")
      refute_received {:text, _, _}

      assert [
               %OutboxMessage{
                 kind: :text,
                 to: "+16045550199",
                 body: "Your SAR Duty confirmation code" <> _
               }
             ] =
               OutboxMessage.list(team)
    end
  end

  test "a demo team's Apple Wallet pass says Sample" do
    team = team_fixture()
    demo_team_fixture(team)
    member = member_fixture(team, %{name: "Cameron Ruiz"})
    card = member |> member_card_fixture() |> Repo.preload(member: [team: :organization])
    config = %{pass_type_id: "pass.test", team_id: "TEAM"}

    json = BuildApplePass.pass_json(card, [], config, DateTime.utc_now())

    assert json.logoText == "Sample card"
    assert [%{label: "Sample, not real ID"}] = json.generic.primaryFields
  end

  test "a demo team's letter PDF draws the Sample mark" do
    letter = %{
      title: "2025 SRVTC Coast Range",
      author: "Coast Range",
      creator: "SARDuty.com",
      content: "Letter"
    }

    real = PDFLetter.render(letter)
    sample = letter |> Map.put(:sample, true) |> PDFLetter.render()

    assert byte_size(sample) > byte_size(real)
  end
end
