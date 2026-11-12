defmodule App.Operation.CheckMemberPhotoTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Operation.CheckMemberPhoto
  alias App.Repo

  defp answer(status), do: Req.Test.stub(App.Adapter.D4H, &Plug.Conn.send_resp(&1, status, ""))

  test "a 200 is a photo; any other answer is none" do
    member = team_fixture() |> member_fixture(%{has_photo: false}) |> Repo.preload(:team)

    answer(200)
    member = CheckMemberPhoto.call(member)
    assert member.has_photo
    assert Repo.reload!(member).has_photo

    answer(404)
    refute CheckMemberPhoto.call(member).has_photo
    refute Repo.reload!(member).has_photo
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
end
