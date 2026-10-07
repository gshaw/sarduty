defmodule Web.TermsLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "anyone can read the terms", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/terms")

    assert has_element?(lv, "#terms h1", "Terms")
    assert has_element?(lv, "#terms-operator", "Gerry Shaw")
    assert has_element?(lv, ~s(#terms-privacy[href="/privacy"]))
  end

  test "the footer links to them", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#footer-terms[href="/terms"]))
  end
end
