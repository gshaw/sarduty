defmodule Web.MeCardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberCard
  alias App.Repo

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  test "shows the member's card, with no way to make one",
       %{conn: conn, team: team, member: member} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/card")
    assert has_element?(lv, "#no-card", "Ask a team admin")
    refute has_element?(lv, "#issue")

    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/card")
    assert has_element?(lv, "#card-code", MemberCard.format_code(card.code))
  end

  test "says when the team has no ID cards",
       %{conn: conn, team: team} do
    team |> Ecto.Changeset.change(id_cards_enabled: false) |> Repo.update!()
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/card")
    assert has_element?(lv, "#no-card", "does not issue")
  end
end
