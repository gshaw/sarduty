defmodule App.Operation.PushPassUpdatesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.BuildApplePass
  alias App.Operation.IssueMemberCard
  alias App.Operation.PushPassUpdates

  @now ~U[2026-09-30 12:00:00.000000Z]

  setup do
    App.ApplePassCredentials.configure()
    team = team_fixture()
    member = member_fixture(team)
    card = member_card_fixture(member, %{authentication_token: "token-0123456789abcdef"})
    PassRegistration.register!(card, "device-1", "push-token-1")
    %{team: team, member: member, card: card}
  end

  defp expect_pushes(test_pid) do
    Req.Test.stub(App.Adapter.APNs, fn conn ->
      send(test_pid, {:pushed, conn.request_path, Plug.Conn.get_req_header(conn, "apns-topic")})
      Plug.Conn.send_resp(conn, 200, "")
    end)
  end

  test "pushes a changed pass once, then not again until it changes", %{team: team, card: card} do
    expect_pushes(self())

    PushPassUpdates.call(team, @now)
    assert_received {:pushed, "/3/device/push-token-1", ["pass.com.sarduty.member-card"]}
    assert Repo.reload!(card).pass_updated_at == @now

    PushPassUpdates.call(team, @now)
    refute_received {:pushed, _, _}
  end

  # A replacement lands on the cancelled card's pass with no new registration (#952).
  test "nudges a replacement's phones until one fetches it", %{team: team, member: member} do
    expect_pushes(self())
    {:ok, replacement} = IssueMemberCard.call(team, member, @now)
    # Replacing pushes the cancelled card to its phone.
    assert_received {:pushed, _, _}

    assert PushPassUpdates.nudge_replacement(replacement, @now) == :ok
    assert_received {:pushed, "/3/device/push-token-1", _topic}
    refute_received {:pushed, _, _}
    assert Repo.reload!(replacement).pass_updated_at == @now

    replacement |> Repo.reload!() |> MemberCard.record_pass_fetched!(@now)
    replacement |> Repo.reload!() |> PushPassUpdates.nudge_replacement(@now)
    refute_received {:pushed, _, _}
  end

  test "nudges nobody for a card no phone has", %{team: team} do
    expect_pushes(self())
    card = member_card_fixture(member_fixture(team))
    PushPassUpdates.nudge_replacement(card, @now)
    refute_received {:pushed, _, _}
  end

  test "doesn't push when only the last-refreshed date moved", %{team: team, card: card} do
    expect_pushes(self())
    team |> refreshed_at(~U[2026-10-01 13:00:00.000000Z]) |> PushPassUpdates.call(@now)
    assert_received {:pushed, _, _}

    team |> refreshed_at(~U[2026-10-02 13:00:00.000000Z]) |> PushPassUpdates.call(@now)
    refute_received {:pushed, _, _}
    assert Repo.reload!(card).pass_updated_at == @now
  end

  test "pushes once a month as valid until rolls forward", %{team: team} do
    expect_pushes(self())
    team |> refreshed_at(~U[2026-10-01 13:00:00.000000Z]) |> PushPassUpdates.call(@now)
    assert_received {:pushed, _, _}

    team |> refreshed_at(~U[2026-11-01 13:00:00.000000Z]) |> PushPassUpdates.call(@now)
    assert_received {:pushed, _, _}
  end

  # A retired or retiring member keeps their card (#893): one push says Not active, and
  # its expiry stays where it was, so Wallet shows it expired within three months.
  test "a member marked retiring gets one push, and their pass stops rolling",
       %{team: team, member: member, card: card} do
    expect_pushes(self())
    team = refreshed_at(team, ~U[2026-10-01 13:00:00.000000Z])
    PushPassUpdates.call(team, @now)
    assert_received {:pushed, _, _}
    expires_at = Repo.reload!(card).expires_at
    assert expires_at == ~U[2027-02-01 06:59:59.000000Z]

    leavers = group_fixture(team)

    team =
      team |> Ecto.Changeset.change(retiring_d4h_group_id: leavers.d4h_group_id) |> Repo.update!()

    group_member_fixture(leavers, member)
    PushPassUpdates.call(team, @now)
    assert_received {:pushed, _, _}

    team |> refreshed_at(~U[2026-11-01 13:00:00.000000Z]) |> PushPassUpdates.call(@now)
    refute_received {:pushed, _, _}
    assert Repo.reload!(card).expires_at == expires_at
  end

  defp refreshed_at(team, refreshed_at) do
    team |> Ecto.Changeset.change(d4h_refreshed_at: refreshed_at) |> Repo.update!()
  end

  test "a changed pass built for an email or download is pushed, not swallowed", %{
    team: team,
    card: card
  } do
    expect_pushes(self())
    Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, 404, ""))
    PushPassUpdates.call(team, @now)
    assert_received {:pushed, _, _}

    team |> Ecto.Changeset.change(name: "Renamed SAR") |> Repo.update!()
    card = MemberCard |> Repo.get!(card.id) |> Repo.preload(member: :team)

    {:ok, _pkpass} = BuildApplePass.call(card, @now)
    assert_received {:pushed, "/3/device/push-token-1", _}

    card |> Repo.reload!() |> Repo.preload(member: :team) |> BuildApplePass.call(@now)
    team |> Repo.reload!() |> PushPassUpdates.call(@now)
    refute_received {:pushed, _, _}
  end

  test "drops a phone Apple says no longer has the pass, and tells the card's pages",
       %{team: team, card: card} do
    Req.Test.stub(App.Adapter.APNs, &Plug.Conn.send_resp(&1, 410, ~s({"reason":"Unregistered"})))
    Phoenix.PubSub.subscribe(App.PubSub, MemberCard.pass_topic(card.member_id))

    PushPassUpdates.call(team, @now)

    assert PassRegistration.get_all_for_serial(card) == []
    assert_received :wallet_changed
  end

  test "drops a phone whose push token Apple calls bad", %{team: team, card: card} do
    Req.Test.stub(
      App.Adapter.APNs,
      &Plug.Conn.send_resp(&1, 400, ~s({"reason":"BadDeviceToken"}))
    )

    PushPassUpdates.call(team, @now)

    assert PassRegistration.get_all_for_serial(card) == []
  end

  test "keeps a phone after any other error", %{team: team, card: card} do
    Req.Test.stub(
      App.Adapter.APNs,
      &Plug.Conn.send_resp(&1, 500, ~s({"reason":"InternalServerError"}))
    )

    PushPassUpdates.call(team, @now)

    assert [_] = PassRegistration.get_all_for_serial(card)
  end

  test "replacing a card pushes its voided pass", %{team: team, member: member, card: card} do
    expect_pushes(self())

    {:ok, _replacement} = IssueMemberCard.call(team, member, @now)

    assert_received {:pushed, "/3/device/push-token-1", _}
    assert Repo.reload!(card).pass_updated_at == @now
  end

  test "does nothing when Apple Wallet isn't set up", %{team: team} do
    Application.put_env(:sarduty, :apple_pass, [])
    assert PushPassUpdates.call(team, @now) == :ok
    refute BuildApplePass.configured?()
  end

  test "a card without a phone is never pushed", %{team: team, member: member} do
    other = member_fixture(team)
    member_card_fixture(other)
    expect_pushes(self())

    PushPassUpdates.call(team, @now)

    assert_received {:pushed, "/3/device/push-token-1", _}
    refute_received {:pushed, _, _}
    assert MemberCard.find_current(team, member)
  end

  describe "after the phone's card was replaced" do
    # The phone registered for the first card. Adding the replacement pass lands on the
    # same Wallet pass, so Wallet never registers again.
    setup %{team: team, member: member} do
      expect_pushes(self())
      {:ok, replacement} = IssueMemberCard.call(team, member, @now)
      assert_received {:pushed, _, _}
      %{replacement: replacement}
    end

    test "replacing the replacement still reaches the phone", %{team: team, member: member} do
      {:ok, _card} = IssueMemberCard.call(team, member, @now)
      assert_received {:pushed, "/3/device/push-token-1", _}
    end

    test "a refresh that changes the replacement reaches the phone", %{
      team: team,
      replacement: replacement
    } do
      PushPassUpdates.call(team, @now)
      assert_received {:pushed, "/3/device/push-token-1", _}
      assert Repo.reload!(replacement).pass_fingerprint
    end

    test "the phone lists the serial once, and unregisters for every card", %{card: card} do
      assert [_, _] = PassRegistration.cards_for_device("device-1", nil)
      PassRegistration.unregister!(card, "device-1")
      assert PassRegistration.get_all_for_serial(card) == []
    end
  end
end
