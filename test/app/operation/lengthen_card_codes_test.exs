defmodule App.Operation.LengthenCardCodesTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo, engine: Oban.Engines.Lite

  import App.DataFixtures

  alias App.Model.MemberCard
  alias App.Operation.LengthenCardCodes
  alias App.Worker.PushPassUpdatesWorker

  test "moves each live 8-character card to 10, keeping its serial and token, and queues each team's push" do
    team = team_fixture()
    other = team_fixture()

    old =
      member_card_fixture(member_fixture(team), %{code: "K7Q4M2XA", authentication_token: "t"})

    cancelled =
      member_card_fixture(member_fixture(team), %{
        code: "K7Q4M2XB",
        revoked_at: ~U[2026-11-01 00:00:00.000000Z]
      })

    new = member_card_fixture(member_fixture(other))

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert LengthenCardCodes.call() == 1
      assert [%{args: %{"team_id" => team_id}}] = all_enqueued(worker: PushPassUpdatesWorker)
      assert team_id == team.id
    end)

    moved = Repo.reload!(old)
    assert String.length(moved.code) == 10
    assert {moved.serial_number, moved.authentication_token} == {old.serial_number, "t"}
    assert Repo.reload!(cancelled).code == "K7Q4M2XB"
    assert Repo.reload!(new).code == new.code

    assert LengthenCardCodes.call() == 0
  end

  test "the old code then matches no card" do
    team = team_fixture()
    card = member_card_fixture(member_fixture(team), %{code: "K7Q4M2XA"})
    LengthenCardCodes.call()

    refute MemberCard.find_by_code("K7Q4M2XA")
    assert MemberCard.find_by_code(Repo.reload!(card).code)
    refute MemberCard.normalize_code("K7Q4-M2XA")
  end
end
