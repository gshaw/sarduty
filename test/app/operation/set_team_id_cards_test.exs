defmodule App.Operation.SetTeamIdCardsTest do
  use App.DataCase

  import App.AccountsFixtures
  import App.DataFixtures

  alias App.Model.Event
  alias App.Model.MemberCard
  alias App.Operation.IssueMemberCard
  alias App.Operation.SetTeamIdCards
  alias App.Repo

  setup do
    %{admin: user_fixture(%{is_admin: true})}
  end

  test "a team with ID cards off can't issue one, and on it can", %{admin: admin} do
    team = team_fixture(%{id_cards_enabled: false})
    member = member_fixture(team)
    now = DateTime.utc_now()

    assert IssueMemberCard.call(team, member, now) == {:error, :id_cards_off}
    assert MemberCard.find_current(team, member) == nil

    {:ok, team} = SetTeamIdCards.call(team, true, admin)
    assert {:ok, %MemberCard{}} = IssueMemberCard.call(team, member, now)
    assert Event.get_last(:id_cards_turned_on).team_id == team.id
  end

  test "turning ID cards off cancels the team's cards, and no other team's", %{admin: admin} do
    team = team_fixture()
    card = team |> member_fixture() |> member_card_fixture()
    other = team_fixture() |> member_fixture() |> member_card_fixture()

    {:ok, team} = SetTeamIdCards.call(team, false, admin)

    refute team.id_cards_enabled
    assert Repo.reload!(card).revoked_at
    refute Repo.reload!(other).revoked_at
    assert Event.get_last(:id_cards_turned_off).data["revoked"] == 1
  end

  test "only a SAR Duty admin may", %{admin: _admin} do
    assert_raise FunctionClauseError, fn ->
      SetTeamIdCards.call(team_fixture(), true, user_fixture())
    end
  end
end
