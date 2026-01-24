defmodule Web.TaxCreditLetterLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders tax credit letter", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    member = member_fixture(team)
    letter = tax_credit_letter_fixture(member)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/tax-credit-letters/#{letter.id}")

    assert html =~ letter.ref_id
  end
end
