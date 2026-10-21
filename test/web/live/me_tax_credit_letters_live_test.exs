defmodule Web.MeTaxCreditLettersLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{team: team, member: member, user: user} = member_with_login_fixture()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  test "lists the member's letters, newest first, and no one else's",
       %{conn: conn, team: team, member: member} do
    older = tax_credit_letter_fixture(member, %{year: 2024})
    newer = tax_credit_letter_fixture(member, %{year: 2025})
    other = tax_credit_letter_fixture(member_fixture(team), %{year: 2025})

    {:ok, lv, html} = live(conn, ~p"/teams/#{team}/me/tax-credit-letters")

    assert has_element?(lv, "#letter-#{newer.id}", "Download 2025 letter")
    assert has_element?(lv, "#letter-#{older.id}", "Download 2024 letter")
    refute has_element?(lv, "#letter-#{other.id}")
    assert :binary.match(html, "letter-#{newer.id}") < :binary.match(html, "letter-#{older.id}")
  end

  test "says when there are no letters yet", %{conn: conn, team: team} do
    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/me/tax-credit-letters")
    assert has_element?(lv, "#no-letters")
  end
end
