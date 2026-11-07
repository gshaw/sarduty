defmodule App.Operation.EmailMemberCardTest do
  use App.DataCase

  import App.DataFixtures
  import Swoosh.TestAssertions

  alias App.Operation.EmailMemberCard

  setup do
    team = team_fixture()
    %{team: team, member: member_fixture(team)}
  end

  # Passes are built on the card's page, when the member taps (#952).
  test "emails the card's link and builds no pass", %{team: team, member: member} do
    App.ApplePassCredentials.configure()
    App.GoogleWalletCredentials.configure()
    Req.Test.stub(App.Adapter.GoogleWallet, fn _conn -> flunk("called Google") end)
    Req.Test.stub(App.Adapter.D4H, fn _conn -> flunk("fetched a photo for a pass") end)
    card = member_card_fixture(member)

    assert :ok = EmailMemberCard.call(team, member)

    assert_email_sent(fn email ->
      assert emailed_card_id(email) == card.id
      assert email.attachments == []
    end)
  end

  test "no email, no send", %{team: team} do
    member = member_fixture(team, %{email: nil})
    member_card_fixture(member)
    assert {:error, :no_email} = EmailMemberCard.call(team, member)
  end

  test "no card, no send", %{team: team, member: member} do
    assert {:error, :no_card} = EmailMemberCard.call(team, member)
  end
end
