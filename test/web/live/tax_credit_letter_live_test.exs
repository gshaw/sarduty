defmodule Web.TaxCreditLetterLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  test "renders tax credit letter", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    letter = tax_credit_letter_fixture(member)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

    assert html =~ letter.ref_id
  end

  test "emails the letter to the member", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    letter = tax_credit_letter_fixture(member)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

    lv |> element("#email-letter") |> render_click()

    assert_email_sent(fn email -> assert email.to == [{"", member.email}] end)
    assert render(lv) =~ "Emailed the tax credit letter to #{member.email}"
  end

  test "says so when the member has no email", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team, %{email: nil})
    letter = tax_credit_letter_fixture(member)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/teams/#{team}/tax-credit-letters/#{letter.id}")

    lv |> element("#email-letter") |> render_click()

    assert_no_email_sent()
    assert render(lv) =~ "has no email in D4H"
  end
end
