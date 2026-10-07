defmodule App.Operation.RefreshD4HData.CheckMemberPhotosTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.RefreshD4HData.CheckMemberPhotos

  # D4H's image endpoint, as seen on a real team (2026-10-07): 200 with a photo, 204
  # with none. Members with an even D4H id have one here.
  defp stub_images(seen) do
    Req.Test.stub(D4H, fn conn ->
      "HEAD" = conn.method
      [_, d4h_id] = Regex.run(~r{/members/(\d+)/image}, conn.request_path)
      send(seen, {:asked, String.to_integer(d4h_id)})
      status = if rem(String.to_integer(d4h_id), 2) == 0, do: 200, else: 204
      Plug.Conn.send_resp(conn, status, "")
    end)
  end

  defp check(team, scope),
    do: team |> D4H.build_context_from_team() |> CheckMemberPhotos.call(team, scope)

  defp has_photo(member), do: Repo.get!(Member, member.id).has_photo

  test "records which current members have a photo, and asks nothing about departed ones" do
    team = team_fixture()
    with_photo = member_fixture(team, %{d4h_member_id: 9_100_002, has_photo: nil})
    without = member_fixture(team, %{d4h_member_id: 9_100_003, has_photo: true})
    left = member_fixture(team, %{d4h_member_id: 9_100_005, left_at: ~U[2025-01-01 00:00:00Z]})
    stub_images(self())

    assert check(team, :current) == 2

    assert has_photo(with_photo) == true
    assert has_photo(without) == false
    refute_received {:asked, 9_100_005}
    assert has_photo(left) == true
  end

  test "the sync asks only about members never checked, and only on its own team" do
    team = team_fixture()
    checked = member_fixture(team, %{d4h_member_id: 9_200_003, has_photo: true})
    new = member_fixture(team, %{d4h_member_id: 9_200_005, has_photo: nil})
    other_team = member_fixture(team_fixture(), %{d4h_member_id: 9_200_007, has_photo: nil})
    stub_images(self())

    assert check(team, :unchecked) == 1

    assert_received {:asked, 9_200_005}
    refute_received {:asked, 9_200_003}
    assert has_photo(new) == false
    assert has_photo(checked) == true
    assert has_photo(other_team) == nil
  end

  test "a D4H error leaves the member as it was" do
    team = team_fixture()
    member = member_fixture(team, %{has_photo: nil})
    Req.Test.stub(D4H, &Plug.Conn.send_resp(&1, 404, ""))

    assert check(team, :current) == 0
    assert has_photo(member) == nil
  end
end
