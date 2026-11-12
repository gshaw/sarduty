defmodule App.Operation.CheckMemberPhotoTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Operation.CheckMemberPhoto
  alias App.Repo

  defp answer(status), do: Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, status, ""))

  # D4H answers 204 for a member with no photo, Records 404.
  test "a 200 is a photo; a 204 or 404 is none" do
    member = team_fixture() |> member_fixture(%{has_photo: false}) |> Repo.preload(:team)

    for none <- [204, 404] do
      answer(200)
      member = CheckMemberPhoto.call(member)
      assert member.has_photo
      assert Repo.reload!(member).has_photo

      answer(none)
      refute CheckMemberPhoto.call(member).has_photo
      refute Repo.reload!(member).has_photo
    end
  end

  # A rate limit or an outage says nothing about the photo. 401 isn't retried, so it's quick.
  test "an answer other than 200, 204, or 404 keeps what was stored" do
    member = team_fixture() |> member_fixture() |> Repo.preload(:team)
    answer(401)

    assert ExUnit.CaptureLog.capture_log(fn -> assert CheckMemberPhoto.call(member).has_photo end) =~
             "photo check failed: HTTP 401"

    assert Repo.reload!(member).has_photo
  end

  test "a request that gets no answer keeps what was stored" do
    member = team_fixture() |> member_fixture() |> Repo.preload(:team)
    Req.Test.stub(App.Adapter.D4H, &Req.Test.transport_error(&1, :timeout))

    assert ExUnit.CaptureLog.capture_log(fn -> assert CheckMemberPhoto.call(member).has_photo end) =~
             "photo check failed"
  end

  test "the nightly check covers counted, current members, card holders too, on a team with ID cards" do
    team = team_fixture(%{id_cards_enabled: true})
    holder = member_fixture(team)
    member_card_fixture(holder)
    waiting = member_fixture(team)
    retired = member_fixture(team, %{left_at: ~U[2020-01-01 00:00:00Z]})
    answer(404)

    CheckMemberPhoto.check_team(team, DateTime.utc_now())

    refute Repo.reload!(holder).has_photo
    refute Repo.reload!(waiting).has_photo
    assert Repo.reload!(retired).has_photo

    off = team_fixture(%{id_cards_enabled: false})
    member = member_fixture(off)
    CheckMemberPhoto.check_team(off, DateTime.utc_now())
    assert Repo.reload!(member).has_photo
  end

  # A card that went out with the placeholder gets the photo on the phones that night.
  # The pass marked changed is what makes phones fetch it (RefreshMemberCard); the push
  # itself is tested with Refresh ID card.
  test "the nightly check refreshes the card of a holder whose first photo it finds" do
    team = team_fixture(%{id_cards_enabled: true})
    found = member_fixture(team, %{has_photo: false})
    found_card = member_card_fixture(found)
    had = member_fixture(team)
    had_card = member_card_fixture(had)
    answer(200)

    CheckMemberPhoto.check_team(team, DateTime.utc_now())

    assert Repo.reload!(found).has_photo
    assert Repo.reload!(found_card).pass_updated_at != found_card.pass_updated_at
    assert Repo.reload!(had_card).pass_updated_at == had_card.pass_updated_at
  end
end
