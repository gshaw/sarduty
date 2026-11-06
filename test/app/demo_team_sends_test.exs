defmodule App.DemoTeamSendsTest do
  # What a Try a demo team sends (#857): one copy of each send, to its visitor, and no
  # texts. Real teams are untouched.
  use App.DataCase, async: true

  import App.AccountsFixtures
  import App.DataFixtures
  import Swoosh.Email, except: [from: 2]
  import Swoosh.TestAssertions

  alias App.Accounts
  alias App.Mailer
  alias App.Model.DemoTeam
  alias App.Model.Member
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
    |> Mailer.for_team(team, {:replies, "Cameron Ruiz"})
  end

  describe "App.Mailer" do
    test "a demo team's email goes to its visitor, marked as a demo" do
      team = team_fixture()
      demo = demo_team_fixture(team, %{email: "morgan@example.com"})

      sent = email(team, [{"Cameron Ruiz", "cameron@example.com"}, "avery@example.com"])

      assert sent.to == [{demo.name, "morgan@example.com"}]
      assert sent.subject == "[Demo] Will you be there? Training night"
      assert sent.text_body =~ ~r/^This is your demo. Cameron Ruiz would get this email/
      assert sent.text_body =~ "Its buttons answer for Cameron"
      assert sent.html_body =~ ~r/^<p style=.*This is your demo/
      assert {:ok, _} = Mailer.deliver(sent)
    end

    test "a real team's email is unchanged" do
      team = team_fixture()
      sent = email(team, {"Cameron Ruiz", "cameron@example.com"})

      assert sent.to == [{"Cameron Ruiz", "cameron@example.com"}]
      assert sent.subject == "Will you be there? Training night"
      assert sent.text_body == "Body"
    end

    test "refuses a demo team's email to anyone but its visitor" do
      team = team_fixture()
      demo_team_fixture(team, %{email: "morgan@example.com"})

      stray =
        new()
        |> to("someone@example.com")
        |> Swoosh.Email.from({"SAR Duty", "noreply@sarduty.com"})
        |> subject("Hi")
        |> text_body("Body")
        |> put_private(:team_id, team.id)

      assert Mailer.deliver(stray) == {:error, :demo_recipient}
      assert {:ok, _} = Mailer.deliver(%{stray | to: [{"", "Morgan@Example.com"}]})
    end
  end

  describe "sends" do
    setup do
      %{user: user, team: team} = user_with_team_fixture()
      demo = demo_team_fixture(team, %{email: user.email})
      starts = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
      activity = activity_fixture(team, %{title: "Training night", started_at: starts})

      members =
        for name <- ["Avery Chen", "Blake Morrison", "Cameron Ruiz"] do
          member = member_fixture(team, %{name: name})
          attendance_fixture(activity, member, %{status: "requested"})
          member
        end

      %{user: user, team: team, demo: demo, activity: activity, members: members}
    end

    test "reminders to 3 members are one email to the visitor, and all 3 are sent", ctx do
      ids = Enum.map(ctx.members, & &1.id)

      assert {:ok, reminders} =
               SendReminders.call(ctx.team, ctx.activity, ctx.user, ids, nil, DateTime.utc_now())

      assert length(reminders) == 3
      assert Enum.all?(reminders, &(Repo.reload!(&1).status == :sent))

      assert_email_sent(fn email ->
        assert email.to == [{"Morgan Visitor", ctx.user.email}]
        assert email.subject == "[Demo] Will you be there? Training night"
        assert email.text_body =~ "Avery Chen would get this email"
      end)

      refute_email_sent()
      assert Repo.aggregate(Reminder, :count) == 3

      assert DemoTeam.copy_text(ctx.team) ==
               "Your demo sent one copy, to #{ctx.user.email}."
    end

    test "tax credit letters for 3 members email the visitor one", ctx do
      ids = Enum.map(ctx.members, & &1.id)
      summary = CreateTaxCreditLetters.call(ctx.team, 2025, ids)

      assert summary.created == 3 and summary.emailing == 1
      assert Repo.aggregate(TaxCreditLetter, :count) == 3
      assert_email_sent(fn email -> assert email.subject =~ ~r/^\[Demo\] 2025 SRVTC/ end)
      refute_email_sent()
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

    test "a demo team's member cannot add a mobile number" do
      %{user: user, team: team} = user_with_team_fixture()
      demo_team_fixture(team)
      member = Repo.get_by!(Member, team_id: team.id, email: user.email)

      assert {:error, "A demo cannot add a mobile number." <> _} =
               ChangeOwnPhone.request(member, user, "604-555-0199")
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
