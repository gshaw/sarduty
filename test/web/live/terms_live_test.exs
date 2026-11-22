defmodule Web.TermsLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "anyone can read the terms", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/terms")

    assert has_element?(lv, "#terms-page h1", "Terms")
    assert has_element?(lv, "#terms-page p", "Gerry Shaw runs SAR Duty")
  end

  test "the footer links to them", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#footer-terms[href="/terms"]))
  end
end
