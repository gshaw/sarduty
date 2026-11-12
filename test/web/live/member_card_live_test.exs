defmodule Web.MemberCardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias App.Model.MemberCard
  alias App.Model.MemberStandingChange
  alias App.Model.PassRegistration
  alias App.Operation.IssueEveryMemberCard
  alias App.Operation.IssueMemberCard
  alias App.Repo
  alias App.ViewData.ChangeHistory

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    # Issue and Replace check the photo first (#1012). The team's records have one.
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
    %{conn: log_in_user(conn, user), user: user, team: team, member: member}
  end

  test "Issue ID card with no photo makes no card and says why", %{conn: conn, team: team} do
    # The stored photo is gone from the team's records by the click.
    member = member_fixture(team, %{name: "Riley Okafor"})
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    lv |> element("#issue") |> render_click()

    assert MemberCard.find_current(team, member) == nil
    assert has_element?(lv, "#flash-error", "Riley Okafor has no photo.")
    assert has_element?(lv, "#flash-error", "Add one, then try again.")
    refute Repo.reload!(member).has_photo
  end

  test "Replace ID card checks the photo live, so one added a minute ago counts",
       %{conn: conn, team: team} do
    member = member_fixture(team, %{has_photo: false})
    old = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    lv |> element("#replace") |> render_click()

    assert Repo.reload!(old).revoked_at
    assert MemberCard.find_current(team, member)
    assert Repo.reload!(member).has_photo
  end

  test "shows the card as the member sees it", %{conn: conn, team: team, member: member} do
    member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    assert has_element?(lv, ~s{#card-image[src^="/cards/"][src*="/image?v="]})
  end

  test "a member's first card gets their Wallet serial, and cards made before keep theirs",
       %{team: team, member: member} do
    {:ok, first} = IssueMemberCard.call(team, member, DateTime.utc_now())
    assert first.serial_number == "member-#{member.id}"

    other = member_fixture(team)
    member_card_fixture(other, %{serial_number: "member-card-5"})
    {:ok, replacement} = IssueMemberCard.call(team, other, DateTime.utc_now())
    assert replacement.serial_number == "member-card-5"
  end

  test "issues a card and emails it", %{conn: conn, team: team, member: member} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#no-card")

    lv |> element("#issue") |> render_click()

    card = MemberCard.find_current(team, member)
    assert has_element?(lv, "#card-code", MemberCard.format_code(card.code))

    url = "#{Web.VerifyHost.url()}/#{MemberCard.format_code(card.code)}"
    assert has_element?(lv, ~s(#card-verify-link[href="#{url}"]))

    assert_email_sent(&(emailed_card_id(&1) == card.id))
    assert has_element?(lv, "#card-emailed", "to #{member.email}")
  end

  test "replaces a card: a new code, the old one stops working, and the new card is emailed",
       %{conn: conn, team: team, member: member} do
    old = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    refute has_element?(lv, "#revoke")

    lv |> element("#replace") |> render_click()

    assert Repo.reload!(old).revoked_at
    card = MemberCard.find_current(team, member)
    assert has_element?(lv, "#card-code", MemberCard.format_code(card.code))
    assert_email_sent(&(emailed_card_id(&1) == card.id))
  end

  test "says when the card's email did not send", %{conn: conn, team: team, member: member} do
    member_card_fixture(member, %{email_status: :failed})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    assert has_element?(lv, "#card-emailed", "Did not send")
  end

  test "a retired member gets no card, and an old one shows not active",
       %{conn: conn, team: team} do
    member = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    assert has_element?(lv, "#no-card", "is retired")
    refute has_element?(lv, "#issue")
    render_click(lv, "issue", %{})
    assert MemberCard.find_current(team, member) == nil

    member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#card-status", "Not active")
    refute has_element?(lv, "#replace")
    refute has_element?(lv, "#email-pass")
  end

  test "a retiring member gets no card, and an old one shows not active (#893)",
       %{conn: conn, team: team, member: member} do
    leavers = group_fixture(team)
    team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()
    group_member_fixture(leavers, member)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#no-card", "is retiring")
    refute has_element?(lv, "#issue")

    member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#card-status", "Not active: #{member.name} is retiring")
    refute has_element?(lv, "#replace")
  end

  describe "Cancel ID card (#964)" do
    setup %{team: team, member: member} do
      leavers = group_fixture(team)

      team =
        team
        |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id)
        |> Repo.update!()

      %{team: team, leavers: leavers, member: member}
    end

    test "only for a member who isn't active: an active member's card can only be replaced",
         %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
      refute has_element?(lv, "#cancel-card")

      render_click(lv, "cancel", %{})
      refute Repo.reload!(card).revoked_at
      assert MemberStandingChange |> Repo.all() == []
    end

    test "cancels a retiring member's card, says when, and history says who",
         %{conn: conn, user: user, team: team, leavers: leavers, member: member} do
      group_member_fixture(leavers, member)
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      assert has_element?(lv, "#cancel-card-hint", "Cancel it if they should not have it at all")
      button = element(lv, "#cancel-card")
      assert render(button) =~ "Cancel #{member.name}&#39;s ID card?"
      assert render(button) =~ "If they come back, issue them a new card."

      render_click(button)

      assert Repo.reload!(card).revoked_at
      assert MemberCard.find_current(team, member) == nil
      assert has_element?(lv, "#no-card", "is retiring, so they cannot get an ID card")
      assert has_element?(lv, "#card-cancelled", "Their last one was cancelled on")
      refute has_element?(lv, "#issue")

      assert [entry] =
               team |> ChangeHistory.for_member(member) |> Enum.filter(&(&1.kind == :standing))

      assert entry.text == "ID card cancelled"
      assert entry.applied_by == user.email
    end

    test "a cancelled card isn't remade while they're retired, and is when they come back",
         %{conn: conn, team: team, member: member} do
      team = team |> Ecto.Changeset.change(every_member_card: true) |> Repo.update!()
      retired = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
      member_card_fixture(retired)
      # Everyone active has a card.
      IssueEveryMemberCard.call(team, DateTime.utc_now())
      assert MemberCard.find_current(team, member)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{retired.id}/card")
      button = element(lv, "#cancel-card")
      assert render(button) =~ "Every member gets a card issues them a new one."

      render_click(button)
      assert IssueEveryMemberCard.call(team, DateTime.utc_now()) == 0
      assert MemberCard.find_current(team, retired) == nil

      retired |> Ecto.Changeset.change(left_at: nil) |> Repo.update!()
      assert IssueEveryMemberCard.call(team, DateTime.utc_now()) == 1
      assert MemberCard.find_current(team, retired)
    end
  end

  test "endorsements: a link to pick them until the team shows some, then the member's",
       %{conn: conn, team: team, member: member} do
    member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#card-qualifications a", "Select endorsements to show")

    endorsement_fixture(team, %{on_card: true})
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
    assert has_element?(lv, "#card-qualifications", "None")
    refute has_element?(lv, "#card-qualifications a")
  end

  test "a team without ID cards sees why, and no way to issue one", %{
    conn: conn,
    team: team,
    member: member
  } do
    team |> Ecto.Changeset.change(id_cards_enabled: false) |> Repo.update!()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    assert has_element?(lv, "#id-cards-off")
    refute has_element?(lv, "#issue")
    render_click(lv, "issue", %{})
    assert MemberCard.find_current(team, member) == nil
  end

  # A pass goes on the member's phone, from Your membership, never the team admin's.
  test "offers no Wallet buttons", %{conn: conn, team: team, member: member} do
    App.ApplePassCredentials.configure()
    App.GoogleWalletCredentials.configure()
    member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

    assert has_element?(lv, "#email-pass")
    refute has_element?(lv, "#apple-pass")
    refute has_element?(lv, "#google-pass")
  end

  describe "with Apple Wallet set up" do
    setup do
      App.ApplePassCredentials.configure()
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 200, png_fixture(640, 480)))
      :ok
    end

    test "emails the card's link to the member", %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      lv |> element("#email-pass") |> render_click()

      assert_email_sent(fn email ->
        assert email.to == [{member.name, member.email}]
        assert emailed_card_id(email) == card.id
        assert email.attachments == []
      end)

      assert render(lv) =~ "Sending the ID card to #{member.email}"
      assert has_element?(lv, "#card-emailed", "to #{member.email}")
    end

    test "offers no email button when D4H has no email", %{conn: conn, team: team} do
      member = member_fixture(team, %{email: nil})
      member_card_fixture(member)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      refute has_element?(lv, "#email-pass")
      assert has_element?(lv, "#card-delivery", "has no email. Add one in D4H")
    end

    test "says how the card reaches the member", %{conn: conn, team: team, member: member} do
      member_card_fixture(member)
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
      assert has_element?(lv, "#card-delivery", "Email it so #{member.name} can add it")

      team |> Ecto.Changeset.change(member_logins: true) |> Repo.update!()
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
      assert has_element?(lv, "#card-delivery", "adds it to Wallet from Your membership")
    end
  end

  describe "a card's phones" do
    setup %{member: member} do
      App.ApplePassCredentials.configure()
      Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))
      %{card: member_card_fixture(member, %{authentication_token: "token-0123456789abcdef"})}
    end

    test "a card in no Wallet says so", %{
      conn: conn,
      team: team,
      member: member
    } do
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      assert has_element?(lv, "#card-phones", "Not in Wallet yet")
    end

    test "shows the phones, and ticks over when a phone fetches",
         %{conn: conn, team: team, member: member, card: card} do
      PassRegistration.register!(card, "device-1", "push-token-1")
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
      assert has_element?(lv, "#card-phones", "In Apple Wallet on 1 device")

      PassRegistration.register!(card, "device-2", "push-token-2")
      MemberCard.record_pass_fetched!(card, ~U[2026-09-30 22:42:00.000000Z])

      assert has_element?(lv, "#card-phones", "In Apple Wallet on 2 devices")
      # Google Wallet has nothing like it (#1012).
      refute render(lv) =~ "last downloaded"
    end

    test "Refresh ID card tells the phones to download it again, with no email",
         %{conn: conn, team: team, member: member, card: card} do
      test_pid = self()
      PassRegistration.register!(card, "device-1", "push-token-1")

      Req.Test.stub(App.Adapter.APNs, fn conn ->
        send(test_pid, {:pushed, conn.request_path})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")
      lv |> element("#refresh-card[phx-disable-with]") |> render_click()

      assert_received {:pushed, "/3/device/push-token-1"}
      assert Repo.reload!(card).pass_updated_at != card.pass_updated_at
      refute Repo.reload!(member).has_photo

      assert has_element?(lv, "#flash-info", "#{member.name}'s ID card refreshed.")
      assert has_element?(lv, "#flash-info", "Phones that hold it get it within a minute.")

      assert_no_email_sent()
    end
  end

  describe "with Google Wallet set up" do
    setup do
      App.GoogleWalletCredentials.configure()
      App.GoogleWalletCredentials.stub(self())
      :ok
    end

    test "says when the card is in Google Wallet", %{conn: conn, team: team, member: member} do
      card = member_card_fixture(member)
      MemberCard.mark_in_wallet!(card, DateTime.utc_now())
      {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/card")

      assert has_element?(lv, "#card-phones", "In Google Wallet")
    end
  end
end
