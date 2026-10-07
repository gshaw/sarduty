defmodule Web.PrivacyLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  test "renders the placeholder", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/privacy")

    assert has_element?(lv, "#privacy-title")
    assert has_element?(lv, "#privacy-placeholder")
  end
end
