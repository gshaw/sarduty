defmodule Web.TaxCreditLetterCollectionLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  test "renders tax credit letters collection", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture()
    _member = member_fixture(team)

    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/#{team.subdomain}/tax-credit-letters")

    assert html =~ "Tax Credit Letters"
  end
end
