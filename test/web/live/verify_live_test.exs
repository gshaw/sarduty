defmodule Web.VerifyLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.MemberCard

  setup do
    team = team_fixture()
    %{team: team, member: member_fixture(team)}
  end

  test "anyone can open the page without logging in", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/verify")
    assert has_element?(lv, "#check-form")
    assert has_element?(lv, "#scanner")
  end

  test "a typed code for a current member shows them as active", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/verify")

    typed = card.code |> MemberCard.format_code() |> String.downcase()
    lv |> form("#check-form", check: %{code: typed}) |> render_submit()

    assert has_element?(lv, "#result-active")
    assert has_element?(lv, "#result-name", member.name)
  end

  test "a scanned code is checked the same way", %{conn: conn, member: member} do
    card = member_card_fixture(member)
    {:ok, lv, _html} = live(conn, ~p"/verify")

    lv |> element("#scanner") |> render_hook("scanned", %{code: card.code})

    assert has_element?(lv, "#result-active")
  end

  test "a member who left shows as not active", %{conn: conn, team: team} do
    member = member_fixture(team, %{left_at: ~U[2026-01-01 00:00:00Z]})
    card = member_card_fixture(member)

    {:ok, lv, _html} = live(conn, ~p"/verify?#{[code: card.code]}")

    assert has_element?(lv, "#result-inactive")
  end

  test "a cancelled card shows no member details", %{conn: conn, member: member} do
    card = member_card_fixture(member, %{revoked_at: DateTime.utc_now()})

    {:ok, lv, html} = live(conn, ~p"/verify?#{[code: card.code]}")

    assert has_element?(lv, "#result-revoked")
    refute html =~ member.name
  end

  test "an unknown or malformed code is not found", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/verify?#{[code: "AAAA-AAAA"]}")
    assert has_element?(lv, "#result-not-found")

    {:ok, lv, _html} = live(conn, ~p"/verify?#{[code: "https://example.com"]}")
    assert has_element?(lv, "#result-not-found")
  end

  test "lists the qualifications the team shows on cards", %{
    conn: conn,
    team: team,
    member: member
  } do
    qualification = qualification_fixture(team)
    clause = group_rule_clause_fixture(group_fixture(team), %{name: "First Aid", on_card: true})
    group_rule_clause_qualification_fixture(clause, qualification)
    qualification_award_fixture(qualification, member)
    card = member_card_fixture(member)

    {:ok, lv, _html} = live(conn, ~p"/verify?#{[code: card.code]}")

    assert has_element?(lv, "#result-qualifications", "First Aid — no expiry")
  end
end
