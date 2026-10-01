defmodule App.Operation.PushPassUpdatesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Model.MemberCard
  alias App.Model.PassRegistration
  alias App.Operation.BuildApplePass
  alias App.Operation.IssueMemberCard
  alias App.Operation.PushPassUpdates
  alias App.Operation.RevokeMemberCard

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

  test "doesn't push when only the last-refreshed date moved", %{team: team, card: card} do
    expect_pushes(self())
    PushPassUpdates.call(team, @now)
    assert_received {:pushed, _, _}

    team
    |> Ecto.Changeset.change(d4h_refreshed_at: ~U[2026-10-01 13:00:00.000000Z])
    |> Repo.update!()

    team |> Repo.reload!() |> PushPassUpdates.call(@now)
    refute_received {:pushed, _, _}
    assert Repo.reload!(card).pass_updated_at == @now
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

  test "drops a phone Apple says no longer has the pass", %{team: team, card: card} do
    Req.Test.stub(App.Adapter.APNs, &Plug.Conn.send_resp(&1, 410, ~s({"reason":"Unregistered"})))

    PushPassUpdates.call(team, @now)

    assert PassRegistration.get_all_for_serial(card) == []
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

  test "cancelling a card pushes its voided pass", %{team: team, member: member, card: card} do
    expect_pushes(self())

    RevokeMemberCard.call(team, member, @now)

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

    test "cancelling the replacement still reaches the phone", %{team: team, member: member} do
      RevokeMemberCard.call(team, member, @now)
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
