defmodule Web.HomePageLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "renders home page", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Welcome to"
  end

  test "the footer links to the verify site", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#footer-verify[href="#{Web.VerifyHost.url()}"]))
  end
end
