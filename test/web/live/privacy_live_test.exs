defmodule Web.PrivacyLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "anyone can read the privacy page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/privacy")

    assert has_element?(lv, "#privacy h1", "Privacy")
    assert has_element?(lv, ~s(#privacy-contact[href^="mailto:"]))
  end

  test "the footer links to it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#footer-privacy[href="/privacy"]))
  end
end
