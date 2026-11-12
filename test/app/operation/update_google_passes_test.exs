defmodule App.Operation.UpdateGooglePassesTest do
  use App.DataCase

  import App.DataFixtures

  alias App.Operation.BuildGooglePass
  alias App.Operation.IssueMemberCard
  alias App.Operation.UpdateGooglePasses
  alias App.Worker.UpdateCardWorker

  @now ~U[2026-09-30 12:00:00.000000Z]

  # What PushPassUpdatesWorker does after a refresh, at a fixed time. Jobs run inline.
  defp refresh(team, now),
    do: team |> UpdateGooglePasses.changed_cards(now) |> UpdateCardWorker.enqueue_all()

  setup do
    App.GoogleWalletCredentials.configure()
    App.GoogleWalletCredentials.stub(self())
    team = team_fixture()
    member = member_fixture(team)
    %{team: team, member: member}
  end

  defp card_on_google(member) do
    member_card_fixture(member, %{google_pass_fingerprint: "old"})
  end

  test "making the pass sends the class and the object, and returns a save link",
       %{member: member} do
    card = member |> member_card_fixture() |> Repo.preload(member: :team)

    assert {:ok, "https://pay.google.com/gp/v/save/" <> _jwt} = BuildGooglePass.call(card, @now)
    assert_received {:google, "PUT", "/walletobjects/v1/genericClass/" <> _, _class}

    assert_received {:google, "PUT", "/walletobjects/v1/genericObject/" <> _,
                     %{"state" => "ACTIVE"}}

    assert Repo.reload!(card).google_pass_fingerprint
  end

  test "sends a changed pass once, then not again until it changes",
       %{team: team, member: member} do
    card = card_on_google(member)

    refresh(team, @now)
    assert_received {:google, "PUT", "/walletobjects/v1/genericClass/" <> _, _class}
    assert_received {:google, "PUT", "/walletobjects/v1/genericObject/" <> _, _object}
    refute Repo.reload!(card).google_pass_fingerprint == "old"

    refresh(team, @now)
    refute_received {:google, _, _, _}
  end

  test "leaves alone cards Google has no pass for", %{team: team, member: member} do
    member_card_fixture(member)
    refresh(team, @now)
    refute_received {:google, _, _, _}
  end

  test "replacing a card expires the old pass", %{team: team, member: member} do
    card_on_google(member)

    {:ok, _card} = IssueMemberCard.call(team, member, @now)

    assert_received {:google, "PUT", _path, %{"state" => "EXPIRED"} = object}
    refute Map.has_key?(object, "barcode")
  end

  test "does nothing when Google Wallet isn't set up", %{team: team, member: member} do
    card_on_google(member)
    Application.put_env(:sarduty, :google_wallet, [])

    refresh(team, @now)
    refute_received {:google, _, _, _}
  end
end
