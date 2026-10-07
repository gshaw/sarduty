defmodule Web.TermsLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "renders the placeholder", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/terms")

    assert has_element?(lv, "#terms-title")
    assert has_element?(lv, "#terms-placeholder")
  end
end
