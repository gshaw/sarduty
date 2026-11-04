defmodule Web.CardApiLiveTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the page and its Markdown give the same check, with this site's verify host", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/agents/id-cards")
    assert has_element?(lv, "#card-api h1", "How to check an ID card")
    assert has_element?(lv, "#card-api a[href='#{Web.VerifyHost.url()}/api/cards/SAMP-ACTV']")

    markdown = conn |> get(~p"/agents/id-cards.md") |> response(200)
    assert markdown =~ "GET #{Web.VerifyHost.url()}/api/cards/K7Q4-M2XA"
  end

  test "Agents lists it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/agents")
    assert has_element?(lv, ~s(#agents-page-id-cards a[href="/agents/id-cards.md"]))
  end
end
