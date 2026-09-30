defmodule Web.MemberCardLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberCard
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    %{conn: log_in_user(conn, user), team: team, member: member}
  end

  test "issues a card", %{conn: conn, team: team, member: member} do
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")
    assert has_element?(lv, "#no-card")

    lv |> element("#issue") |> render_click()

    card = MemberCard.find_current(team, member)
    assert has_element?(lv, "#card-code", MemberCard.format_code(card.code))
  end

  test "replacing a card cancels the old one", %{conn: conn, team: team, member: member} do
    old = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")

    lv |> element("#replace") |> render_click()

    assert Repo.reload!(old).revoked_at
    new = MemberCard.find_current(team, member)
    assert new.code != old.code
    assert has_element?(lv, "#card-code", MemberCard.format_code(new.code))
  end

  test "cancels a card", %{conn: conn, team: team, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/#{team.subdomain}/members/#{member.id}/card")

    lv |> element("#revoke") |> render_click()

    assert Repo.reload!(card).revoked_at
    assert has_element?(lv, "#no-card")
  end
end
