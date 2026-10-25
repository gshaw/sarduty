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

  test "a SAR Duty admin or the team's organization admins may; anyone else is refused" do
    team = team_fixture(%{id_cards_enabled: false})
    organization = organization_fixture([team])
    dana = user_fixture()
    organization_admin_fixture(organization, dana.email)
    stranger = user_fixture()
    other_admin = user_fixture()
    organization_admin_fixture(organization_fixture(), other_admin.email)
    team = Repo.reload!(team)

    assert SetTeamIdCards.call(team, true, stranger) == {:error, :forbidden}
    assert SetTeamIdCards.call(team, true, other_admin) == {:error, :forbidden}
    assert {:ok, %{id_cards_enabled: true}} = SetTeamIdCards.call(team, true, dana)
    assert Event.get_last(:id_cards_turned_on).user_id == dana.id
  end

  test "a team taken out of the organization is refused, even from a page loaded before" do
    team = team_fixture(%{id_cards_enabled: true})
    organization = organization_fixture([team])
    dana = user_fixture()
    organization_admin_fixture(organization, dana.email)
    loaded = Repo.reload!(team)

    loaded |> Ecto.Changeset.change(organization_id: nil) |> Repo.update!()

    assert SetTeamIdCards.call(loaded, false, dana) == {:error, :forbidden}
    assert Repo.reload!(team).id_cards_enabled
  end

  test "each change emails the team's team admins, naming who acted", %{admin: admin} do
    team = team_fixture(%{name: "Coast Range SAR"})
    manager_fixture(team, %{email: "owner@example.com"})
    team |> member_fixture() |> member_card_fixture()

    {:ok, team} = SetTeamIdCards.call(team, false, admin)

    assert_received {:email, %{to: [{"", "owner@example.com"}]} = email}
    assert email.subject == "ID cards are off for Coast Range SAR"
    assert email.reply_to == {"", "support@sarduty.com"}
    assert email.text_body =~ "#{admin.email} turned off ID cards for Coast Range SAR"
    assert email.text_body =~ "Its 1 card is cancelled."

    {:ok, _team} = SetTeamIdCards.call(team, true, admin)
    assert_received {:email, %{subject: "ID cards are on for Coast Range SAR"}}
  end
end
